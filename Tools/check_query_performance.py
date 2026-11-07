#!/usr/bin/env python3
"""Exercise migration SQL and loading query plans on a deterministic large SQLite fixture.

This is a database microbenchmark, not an iOS launch benchmark. Timings are
informational; plan shape and unchanged results are the regression gates.
"""

import argparse
from pathlib import Path
import re
import sqlite3
from statistics import median
from time import perf_counter

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "Packages/HardsetKit/Sources/HardsetStore/Migrations.swift"

# Same predicates and ordering as VolumeStore, ProgressionStore and LoggerStore.
QUERIES = {
    "rolling volume": (
        'SELECT * FROM loggedSets WHERE completedAt >= ? AND completedAt < ? ORDER BY completedAt',
        ("2026-10-28", "2026-11-04"),
    ),
    "progression": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND NOT isWarmup ORDER BY completedAt DESC LIMIT 2000',
        ("exercise-3",),
    ),
    "machine history": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND machineID IS NULL AND NOT isWarmup ORDER BY completedAt DESC LIMIT 1000',
        ("exercise-3",),
    ),
    "session recovery": (
        'SELECT * FROM loggedSets WHERE sessionID = ? ORDER BY setOrdinal',
        ("session-100",),
    ),
    "session plan": (
        'SELECT * FROM sessionExercises WHERE sessionID = ? ORDER BY position',
        ("session-100",),
    ),
}


def statements(source):
    # Only literal SQL: fail explicitly if migrations switch to interpolated SQL.
    blocks = re.findall(r'try #sql\(\s*"""(.*?)"""\s*\)\s*\.execute\(db\)', source, re.S)
    assert blocks, "No migration SQL found"
    assert all("\\(" not in block for block in blocks), "Interpolated SQL needs a native test"
    return blocks


def measure(db, query, arguments):
    plan = [row[3] for row in db.execute("EXPLAIN QUERY PLAN " + query, arguments)]
    timings = []
    for _ in range(5):
        start = perf_counter()
        rows = db.execute(query, arguments).fetchall()
        timings.append((perf_counter() - start) * 1000)
    return rows, median(timings), plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-indexes", action="store_true")
    args = parser.parse_args()
    source = MIGRATIONS.read_text()
    boundary = source.find('migrator.registerMigration("v2_loadingIndexes")')
    baseline = source if boundary < 0 else source[:boundary]
    upgrade = "" if boundary < 0 else source[boundary:]
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    db.create_function("uuid", 0, lambda: "fixture-default-id")
    for statement in statements(baseline):
        db.execute(statement)
    db.executemany('INSERT INTO exercises (id) VALUES (?)', [(f"exercise-{i}",) for i in range(50)])
    db.executemany('INSERT INTO sessions (id) VALUES (?)', [(f"session-{i}",) for i in range(5000)])
    db.executemany(
        'INSERT INTO loggedSets (id, sessionID, exerciseID, setOrdinal, weightKg, reps, isWarmup, completedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ((f"set-{i}", f"session-{i // 20}", f"exercise-{(i // 4) % 50}", i % 20,
          50.0, 8, int(i % 4 == 0), f"2026-{1 + i // 9000:02}-{1 + (i // 300) % 28:02}T{i % 24:02}:{i % 60:02}:00")
         for i in range(100_000)),
    )
    db.executemany(
        'INSERT INTO sessionExercises (id, sessionID, exerciseID, position) VALUES (?, ?, ?, ?)',
        ((f"plan-{i}", f"session-{i // 5}", f"exercise-{i % 50}", i % 5) for i in range(25_000)),
    )
    before = {name: measure(db, *query) for name, query in QUERIES.items()}
    if upgrade:
        for statement in statements(upgrade):
            db.execute(statement)
    failures = []
    for name, query in QUERIES.items():
        rows, elapsed, plan = measure(db, *query)
        old_rows, old_elapsed, old_plan = before[name]
        # Ordering ties are deliberately unspecified by the Store API.
        assert sorted(rows) == sorted(old_rows), f"{name}: results changed"
        assert rows, f"{name}: empty fixture cannot verify a loading query"
        print(f"{name}: {old_elapsed:.3f} -> {elapsed:.3f} ms ({len(rows)} rows)")
        print(f"  before: {'; '.join(old_plan)}")
        print(f"  after:  {'; '.join(plan)}")
        if any("SCAN " in step or "TEMP B-TREE" in step for step in plan):
            failures.append(name)
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    assert db.execute("SELECT count(*) FROM loggedSets").fetchone()[0] == 100_000
    if args.require_indexes and failures:
        raise SystemExit("Unbounded scan or sort in: " + ", ".join(failures))
    print("Migration preserves fixture rows and query results; foreign keys valid.")


if __name__ == "__main__":
    main()
