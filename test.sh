#!/bin/bash
# Runs the full HardsetKit suite.
#
# The engine-dependent tests each need a fresh process: SQLiteData's non-live `SyncEngine`
# attaches an in-memory metadatabase at a fixed shared-cache path, and the task local that
# resets it between constructions is `package`-scoped, so two engines in one process contend
# for the same SQLite file. Everything else runs together.
set -uo pipefail
cd "$(dirname "$0")/Packages/HardsetKit" || exit 1

FAIL=0
echo "=== engine-independent suites ==="
swift test --disable-sandbox --skip "SyncDelegateTests" || FAIL=1

for t in signOutPreservesData switchAccountsPreservesData accountChangeIsReported; do
  echo "=== $t (isolated process) ==="
  swift test --disable-sandbox --filter "$t" || FAIL=1
done

if [ "$FAIL" -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "FAILURES PRESENT"; fi
exit "$FAIL"
