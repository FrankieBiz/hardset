# Phase 0 — Linux Verification Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** make `HardsetCore` and `HardsetStore` (sync excluded) build and test on this Linux
machine from the real package, using one script, without changing what Apple platforms compile.

**Architecture:** the Apple-only code (`CloudKit`) moves behind `#if canImport(CloudKit)`.
`Package.swift` omits the SwiftUI and AlarmKit targets on Linux. The store tests share one
`Configuration` helper, which registers the `uuid()` SQL function Linux's SQLite lacks. A
container image (`swift:6.2` plus `libsqlite3-dev`) runs `swift test` against a bind mount.

**Tech Stack:** Swift 6.2 (container), SwiftPM, GRDB 7.11, SQLiteData 1.10, podman, bash.

**Spec:** `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md` §5 and §6.

## Global Constraints

- Apple builds must be unchanged. Every edit to production sources is an `#if` guard or an
  explicit import. No logic changes.
- The real `Package.swift` is used. There are no overlay manifests or copied sources.
- Linux build products go to `Packages/HardsetKit/.build-linux`, never `.build`, so a Mac
  checkout's cache is never polluted.
- Never `git push`. Commit locally only.
- Commit messages explain *why*. Each ends with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never hand-edit `ExerciseCatalog.swift`.

## Review Focus

- **A Mac build silently loses the sync delegate.** The `#if canImport(CloudKit)` must wrap
  exactly `HardsetSyncDelegate` and `makeSyncEngine`, and nothing on Apple can lose them.
  Expected: on Darwin `canImport(CloudKit)` is true, so the code is identical.
- **A `uuid()` helper that recurses.** A previous probe's sed rewrote the helper's own
  `Configuration()` call into a call to itself, and every DB test segfaulted. The helper must
  spell `GRDB.Configuration()`.
- **A schema test silently disappears on Linux.** Only the single test that constructs a
  `SyncEngine` may be guarded. The other eight `SchemaTests` must still run here.
- **The script runs on a stale image or the wrong mount.** It must build the image when missing
  and fail loudly if podman is absent.
- **Products referencing omitted targets.** On Linux the products list must not name
  `HardsetAlarm`, `HardsetUI` or `HardsetFeature`.

---

### Task 0.1: Guard the CloudKit-only store code and make the package build on Linux

**Files:**
- Modify: `Packages/HardsetKit/Package.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SyncSetup.swift` (line 1 `import CloudKit`;
  lines 75–134 `HardsetSyncDelegate`)
- Modify: `Packages/HardsetKit/Sources/HardsetStore/Database.swift` (line 19 `attachMetadatabase`;
  lines 56–73 `makeSyncEngine`)
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift` (imports)
- Create: `Tools/linux/Containerfile`
- Create: `Tools/linux-test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `Tools/linux-test.sh [swift test args…]`. It exits 0 when every suite passes. Later
  tasks run it as their verification step.

- [ ] **Step 1: Create the container definition**

`Tools/linux/Containerfile`:

```dockerfile
# The Linux test image: Apple's swift:6.2 plus the SQLite headers GRDB links against.
# Only HardsetCore and HardsetStore build here -- see Tools/linux-test.sh.
FROM docker.io/library/swift:6.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Create the runner script**

`Tools/linux-test.sh` (make it executable with `chmod +x`):

```bash
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
```

Add to `.gitignore`:

```
Packages/*/.build-linux/
```

- [ ] **Step 3: Run it to confirm the current failure**

Run: `Tools/linux-test.sh`
Expected: FAIL, with `error: no such module 'SwiftUI'` (or `'CloudKit'`). The manifest still
includes the UI targets and the store still imports CloudKit unconditionally.

- [ ] **Step 4: Make the manifest omit Apple-only targets on Linux**

In `Package.swift`, keep the existing settings and comments, but build `products` and `targets`
as arrays so the Apple-only entries can be appended conditionally. The resulting shape:

```swift
var products: [Product] = [
  .library(name: "HardsetCore", targets: ["HardsetCore"]),
  .library(name: "HardsetStore", targets: ["HardsetStore"]),
]
var targets: [Target] = [
  // (HardsetCore target, unchanged, with its existing comment)
  // (HardsetStore target, unchanged)
  // (HardsetCoreTests, unchanged)
  // (HardsetStoreTests, unchanged)
]

// Linux is a test-execution affordance, like the `.macOS` platform entry above: HardsetCore and
// HardsetStore build there, so their suites run on a machine with no Xcode. AlarmKit, SwiftUI
// and the composition root exist only in Apple SDKs, so they are simply not declared.
#if !os(Linux)
products += [
  .library(name: "HardsetAlarm", targets: ["HardsetAlarm"]),
  .library(name: "HardsetUI", targets: ["HardsetUI"]),
  .library(name: "HardsetFeature", targets: ["HardsetFeature"]),
]
targets += [
  // (HardsetAlarm, HardsetUI, HardsetFeature targets, unchanged, with their existing comments)
]
#endif

let package = Package(
  name: "HardsetKit",
  platforms: [.iOS("26.1"), .macOS("15.0")],
  products: products,
  dependencies: [ /* unchanged */ ],
  targets: targets
)
```

Keep the order products are declared in on Apple identical in meaning. Order does not affect
Xcode, but keep the diff readable.

- [ ] **Step 5: Guard the CloudKit-only store code**

`SyncSetup.swift`: wrap line 1 and the delegate class only.

```swift
#if canImport(CloudKit)
import CloudKit
#endif
import Foundation
import SQLiteData
import Synchronization
```

Wrap `public nonisolated final class HardsetSyncDelegate … }` (from its doc comment through its
closing brace) in `#if canImport(CloudKit)` / `#endif`. Add this comment above the `#if`:

```swift
// The delegate needs CloudKit, which exists only on Apple platforms. `AccountChange` and
// `AccountChangePolicy` above are pure and stay unguarded so their tests run on Linux too.
```

`Database.swift`: in `open`, guard the attach.

```swift
    configuration.prepareDatabase { db in
      // Attaches SQLiteData's sync metadatabase under the `sqlitedata_icloud` schema. CloudKit
      // only: on Linux (tests only) there is no sync engine to attach for.
      #if canImport(CloudKit)
      try db.attachMetadatabase(containerIdentifier: containerIdentifier)
      #endif
    }
```

Then wrap `makeSyncEngine` (from `public static func makeSyncEngine(` through its closing `}`)
in `#if canImport(CloudKit)` / `#endif`. Leave the doc comment directly above the `#if`.

`SessionCoordinator.swift`: add `import Observation` after `import Foundation`, with the
comment:

```swift
// Explicit: on Apple platforms `@Observable` arrives transitively, on Linux it does not.
import Observation
```

- [ ] **Step 6: Build only, to see what is left**

Run: `Tools/linux-test.sh --filter HardsetCoreTests`
Expected: the store test target fails to compile. The errors are `no such module 'CloudKit'`
in `SchemaTests.swift`, `SyncDelegateTests.swift` and `SyncEngineRetentionTests.swift`. Fixed in
Task 0.2.

- [ ] **Step 7: Commit**

```bash
git add Packages/HardsetKit/Package.swift Packages/HardsetKit/Sources/HardsetStore \
  Tools/linux Tools/linux-test.sh .gitignore
git commit -m "build: let HardsetCore and HardsetStore compile on Linux

Development now happens on a Linux machine without Xcode. Everything with behaviour
already lives in these two targets, so guarding the CloudKit-only code and leaving
the SwiftUI and AlarmKit targets out of the Linux manifest is enough to build them.
Apple builds see identical code: every change is a canImport/os guard or an import
that was previously transitive.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 0.2: Make the store suite run on Linux

**Files:**
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/TestDatabase.swift`
- Modify: all 18 `Configuration()` call sites under `Packages/HardsetKit/Tests/HardsetStoreTests/`
- Modify: `SchemaTests.swift`, `SyncDelegateTests.swift`, `SyncEngineRetentionTests.swift`
- Modify: `README.md` (Running the tests section; the stale "Not yet true … never been compiled"
  paragraph)
- Create: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `Tools/linux-test.sh` (Task 0.1).
- Produces: `Configuration.forTesting() -> GRDB.Configuration`. Every later store test that
  builds a database must use it instead of `Configuration()`.

- [ ] **Step 1: Write the shared configuration helper**

`TestDatabase.swift`:

```swift
import Foundation
import GRDB

extension Configuration {
  /// The configuration every store test builds its database from.
  ///
  /// Exists because the schema's primary keys default to `uuid()`, which Apple's SQLite
  /// provides and the Linux distribution's does not. Without it every insert on Linux fails
  /// with "unknown function: uuid()". On Darwin this adds nothing, so Apple runs are unchanged.
  ///
  /// `GRDB.Configuration()` is spelled out on purpose: a bulk replace of `Configuration()` with
  /// `Configuration.forTesting()` must not turn this line into infinite recursion. A probe did
  /// exactly that, and every database test segfaulted.
  static func forTesting() -> Configuration {
    var configuration = GRDB.Configuration()
    #if !canImport(Darwin)
    configuration.prepareDatabase { db in
      db.add(
        function: DatabaseFunction("uuid", argumentCount: 0, pure: false) { _ in
          UUID().uuidString.lowercased()
        }
      )
    }
    #endif
    return configuration
  }
}
```

- [ ] **Step 2: Route every store test through it**

Run:

```bash
rg -l '= Configuration\(\)' Packages/HardsetKit/Tests/HardsetStoreTests \
  | xargs sed -i 's/= Configuration()/= Configuration.forTesting()/'
rg -n 'Configuration\(\)' Packages/HardsetKit/Tests/HardsetStoreTests
```

Expected from the second command: exactly one hit, `TestDatabase.swift` (`GRDB.Configuration()`).

- [ ] **Step 3: Guard the sync-only tests**

- `SyncDelegateTests.swift` and `SyncEngineRetentionTests.swift`: put `#if canImport(CloudKit)`
  as the first line and `#endif` as the last line, with the comment
  `// CloudKit-only: SyncEngine does not exist on Linux. Run on the Mac via ./test.sh.`
- `SchemaTests.swift`: guard `import CloudKit` the same way. Guard **only**
  `syncEngineAcceptsSchema()`, from its doc comment through its closing brace. The other eight
  tests are pure pragma checks and must keep running on Linux.

- [ ] **Step 4: Run the whole suite**

Run: `Tools/linux-test.sh`
Expected: `Test run with N tests in M suites passed`, with N ≥ 280. Record the exact N and M. A
2026-10-10 probe with the same changes got 285 tests in 38 suites, but that probe also guarded
the eight pure `SchemaTests` and `AccountChangePolicyTests`, so expect a few more here.

- [ ] **Step 5: Create the Mac verification ledger**

`docs/MAC-VERIFICATION.md`:

```markdown
# Mac verification ledger

Development happens on Linux, where only HardsetCore and HardsetStore (sync excluded) compile.
Everything else is written blind. Every commit that touches code the Linux harness cannot build
adds an entry here: what to build or run on the Mac, and what must be true. Same rule as
`DEVICE-CHECKLIST.md`: an unchecked box is not "probably fine".

How to run: pull the branch on the Mac, then `./test.sh` (full suite, including sync) and build
the `Hardset` scheme for the iOS 26.4 simulator.

## Phase 0

- [ ] `./test.sh` passes on the Mac. Proves the `#if canImport(CloudKit)` guards and the
      `Configuration.forTesting()` helper changed nothing on Darwin. The sync suites must still
      run there.
- [ ] `Hardset.xcodeproj` opens and the app builds after the manifest became conditional.
      Expected: no change, since `os(Linux)` is false on macOS.
```

- [ ] **Step 6: Update the README**

In `README.md`:
- Replace the "**Not yet true:**" paragraph with one sentence: the app builds and runs in the
  simulator (see `DEVICE-CHECKLIST.md` §A), and has never run on a physical device.
- Under "Running the tests", add after the `./test.sh` block:

```markdown
On Linux (no Xcode), the Core and Store suites run in a container:

    Tools/linux-test.sh            # needs podman; builds the image on first run

Sync, UI, AlarmKit and the app target cannot build there. What they still need checking on the
Mac is listed in `docs/MAC-VERIFICATION.md`.
```

- [ ] **Step 7: Commit**

```bash
git add Packages/HardsetKit/Tests README.md docs/MAC-VERIFICATION.md
git commit -m "test: run the store suite on Linux

Linux's SQLite has no uuid(), which every primary key defaults to, so the store
tests now share a configuration that registers one off Darwin. Only the tests that
construct a SyncEngine are guarded; the schema pragma checks still run here. The
ledger starts here because from now on most changes are written somewhere they
cannot be compiled.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 0.3: Re-baseline the project generator

**Files:**
- Modify: `Hardset.xcodeproj/project.pbxproj` (regenerated, not hand-edited)
- Modify: `docs/MAC-VERIFICATION.md`

Background: the committed `.pbxproj` has hand-edited IDs for the `HardsetFeature` package
product (`A1F0C0DE0000000000000001/2`). The generator produces `654F079C…` and `2F14F12B…`.
That 22-line diff is the only difference, which was verified on 2026-10-10. Any future
regeneration would rewrite those IDs anyway, so the file is regenerated now. A later diff should
then show only intended changes.

- [ ] **Step 1: Regenerate and inspect the diff**

Run:

```bash
python3 Tools/generate_project.py
git diff --stat Hardset.xcodeproj/project.pbxproj
git diff Hardset.xcodeproj/project.pbxproj | rg '^[+-]' | rg -v 'HardsetFeature|^(\+\+\+|---)'
```

Expected: `1 file changed, 11 insertions(+), 11 deletions(-)`, and the last command prints
nothing. Every changed line mentions `HardsetFeature`. If anything else changed, stop and
report it instead of committing.

- [ ] **Step 2: Confirm the generator is now idempotent**

Run:

```bash
cp Hardset.xcodeproj/project.pbxproj /tmp/first.pbxproj
python3 Tools/generate_project.py
cmp /tmp/first.pbxproj Hardset.xcodeproj/project.pbxproj && echo IDEMPOTENT
```

Expected: `IDEMPOTENT`.

- [ ] **Step 3: Add the ledger line and commit**

Append to the Phase 0 section of `docs/MAC-VERIFICATION.md`:

```markdown
- [ ] After the generator re-baseline, Xcode still resolves the `HardsetFeature` package product
      for the app target. Only its object IDs changed.
```

```bash
git add Hardset.xcodeproj/project.pbxproj docs/MAC-VERIFICATION.md
git commit -m "build: regenerate the project so the generator owns it again

The HardsetFeature package-product IDs had been hand-edited, so the next run of the
generator would have silently rewritten them inside an unrelated change. Regenerating
now keeps every later project diff down to what that change actually did.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
