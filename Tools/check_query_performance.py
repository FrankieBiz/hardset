#!/usr/bin/env python3
"""Exercise migration SQL and loading query plans on a deterministic large SQLite fixture.

This is a database microbenchmark, not an iOS launch benchmark. Timings are
informational; plan shape and unchanged results are the regression gates.
"""

import argparse
from datetime import datetime, timedelta
from pathlib import Path
import re
import sqlite3
from statistics import median
from time import perf_counter

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "Packages/HardsetKit/Sources/HardsetStore/Migrations.swift"

# Same predicates and ordering as VolumeStore, ProgressionStore and LoggerStore.
QUERIES = {
    "open workout (absent)": (
        'SELECT * FROM sessions WHERE finishedAt IS NULL ORDER BY startedAt DESC LIMIT 1',
        (),
    ),
    "rolling volume": (
        'SELECT * FROM loggedSets WHERE completedAt >= ? AND completedAt < ? ORDER BY completedAt',
        ("2026-10-28", "2026-11-04"),
    ),
    "progression": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND NOT isWarmup ORDER BY completedAt DESC, setOrdinal DESC, id DESC',
        ("exercise-3",),
    ),
    "machine history": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND machineID IS NULL AND NOT isWarmup ORDER BY completedAt DESC LIMIT 1000',
        ("exercise-3",),
    ),
    "last finished workout": (
        'SELECT id, gymID, title, notes, startedAt, finishedAt FROM sessions WHERE finishedAt IS NOT NULL AND notes NOT LIKE ? ORDER BY finishedAt DESC LIMIT 1',
        ("Imported from %",),
    ),
    "session recovery": (
        'SELECT * FROM loggedSets WHERE sessionID = ? ORDER BY setOrdinal',
        ("session-100",),
    ),
    # Names the columns the fixture had before the upgrade: an additive migration widens
    # SELECT *, which is not a change in the rows this query returns.
    "session plan": (
        'SELECT id, sessionID, exerciseID, machineID, position, plannedSets FROM sessionExercises WHERE sessionID = ? ORDER BY position',
        ("session-100",),
    ),
    "snapshot heaviest": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND machineID IS NULL AND NOT isWarmup AND sessionID IS NOT ? ORDER BY weightKg DESC, reps DESC, completedAt DESC, id DESC LIMIT 1',
        ("exercise-3", "session-100"),
    ),
    "record heaviest at or above reps": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND machineID IS NULL AND NOT isWarmup AND reps >= ? ORDER BY weightKg DESC, reps DESC, completedAt DESC, id DESC LIMIT 1',
        ("exercise-3", 8),
    ),
    "progress board sets": (
        'SELECT exerciseID, machineID, sessionID, weightKg, reps, completedAt FROM loggedSets WHERE NOT isWarmup',
        (),
    ),
    "record best at reps": (
        'SELECT * FROM loggedSets WHERE exerciseID = ? AND machineID IS NULL AND NOT isWarmup AND reps = ? AND weightKg > 0 AND weightKg <= ? ORDER BY weightKg DESC LIMIT 1',
        ("exercise-3", 8, 1000),
    ),
}

# Queries that return a whole table's worth by design, so they cannot be a keyed lookup: the work
# is the size of the answer. They may scan, but they may not sort or build a temporary tree.
WHOLE_HISTORY = {"progress board sets"}


def is_unbounded(name, plan):
    for step in plan:
        if "TEMP B-TREE" in step:
            return True
        if "SCAN " in step and name not in WHOLE_HISTORY:
            return True
    return False


# Queries over tables and columns that only exist after the upgrade, so there is nothing to
# compare them with before it. They are held to the same plan gate: no scan and no sort.
UPGRADED_QUERIES = {
    "template last done": (
        'SELECT templateID, max(startedAt) FROM sessions WHERE templateID IS NOT NULL AND finishedAt IS NOT NULL GROUP BY templateID',
        (),
    ),
    "template last session": (
        'SELECT id FROM sessions WHERE templateID = ? AND finishedAt IS NOT NULL ORDER BY startedAt DESC LIMIT 1',
        ("template-1",),
    ),
    "template movements": (
        'SELECT * FROM templateExercises WHERE templateID IN (?, ?)',
        ("template-1", "template-2"),
    ),
}


def seed_saved_workouts(db):
    """Three saved workouts of four movements each, and a tenth of the sessions started from them."""
    db.executemany(
        'INSERT INTO workoutTemplates (id, name, position) VALUES (?, ?, ?)',
        [(f"template-{i}", f"Workout {i}", i) for i in range(3)],
    )
    db.executemany(
        'INSERT INTO templateExercises (id, templateID, exerciseID, position, plannedSets) VALUES (?, ?, ?, ?, 3)',
        ((f"template-exercise-{i}", f"template-{i // 4}", f"exercise-{i % 50}", i % 4) for i in range(12)),
    )
    db.execute(
        "UPDATE sessions SET templateID = 'template-' || (CAST(substr(id, 9) AS INTEGER) % 3) "
        "WHERE CAST(substr(id, 9) AS INTEGER) % 10 = 0"
    )


def statements(source):
    # Only literal SQL: fail explicitly if migrations switch to interpolated SQL.
    blocks = re.findall(r'try #sql\(\s*"""(.*?)"""\s*\)\s*\.execute\(db\)', source, re.S)
    assert blocks, "No migration SQL found"
    assert all("\\(" not in block for block in blocks), "Interpolated SQL needs a native test"
    return blocks


def apply_migration_sql(db, source):
    for statement in statements(source):
        # v5 conditionally repairs legacy columns. Fresh v1 already includes
        # them; mirror those metadata guards for this literal-SQL benchmark.
        # Native Store tests execute the real migrator on all legacy variants.
        addition = re.search(r'ALTER TABLE "(\w+)" ADD COLUMN "(\w+)"', statement)
        if addition:
            table, column = addition.groups()
            if column in {row[1] for row in db.execute(f'PRAGMA table_info("{table}")')}:
                continue
        db.execute(statement)


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
    apply_migration_sql(db, baseline)
    db.executemany('INSERT INTO exercises (id) VALUES (?)', [(f"exercise-{i}",) for i in range(50)])
    db.executemany(
        'INSERT INTO sessions (id, startedAt, finishedAt) VALUES (?, ?, ?)',
        [(f"session-{i}", (datetime(2012, 1, 1) + timedelta(days=i)).isoformat(),
          (datetime(2012, 1, 1, 1) + timedelta(days=i)).isoformat()) for i in range(5000)],
    )
    assert db.execute('SELECT count(*) FROM sessions WHERE finishedAt IS NULL').fetchone()[0] == 0
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
        apply_migration_sql(db, upgrade)
    failures = []
    for name, query in QUERIES.items():
        rows, elapsed, plan = measure(db, *query)
        old_rows, old_elapsed, old_plan = before[name]
        # Compare all values; progression now also specifies stable ordinal/ID ties.
        assert sorted(rows) == sorted(old_rows), f"{name}: results changed"
        if name == "open workout (absent)":
            assert rows == [], "Finished history must not resume a workout"
        else:
            assert rows, f"{name}: empty fixture cannot verify a loading query"
        print(f"{name}: {old_elapsed:.3f} -> {elapsed:.3f} ms ({len(rows)} rows)")
        print(f"  before: {'; '.join(old_plan)}")
        print(f"  after:  {'; '.join(plan)}")
        if is_unbounded(name, plan):
            failures.append(name)
    if upgrade:
        seed_saved_workouts(db)
        for name, (query, arguments) in UPGRADED_QUERIES.items():
            rows, elapsed, plan = measure(db, query, arguments)
            assert rows, f"{name}: empty fixture cannot verify a loading query"
            print(f"{name}: {elapsed:.3f} ms ({len(rows)} rows)")
            print(f"  after:  {'; '.join(plan)}")
            if is_unbounded(name, plan):
                failures.append(name)
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    assert db.execute("SELECT count(*) FROM loggedSets").fetchone()[0] == 100_000
    if args.require_indexes and failures:
        raise SystemExit("Unbounded scan or sort in: " + ", ".join(failures))
    print("Migration preserves fixture rows and query results; foreign keys valid.")


if __name__ == "__main__":
    main()
