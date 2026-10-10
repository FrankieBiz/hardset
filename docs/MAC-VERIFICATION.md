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
