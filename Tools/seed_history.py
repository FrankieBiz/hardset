#!/usr/bin/env python3
"""Seed a simulator install with a realistic *length* of training history.

Why this exists. Every defect found in this app's progress surfaces so far was found by running it
with months of data, and none by the test suite -- history silently truncated at 50 workouts, a
volume tab with no way to look back, a chart reachable only sideways. A week of data hides all of
them, and a week of data is what a hand-driven walkthrough produces. So this writes twenty weeks.

It writes through sqlite3 directly rather than through the app, on purpose: the point is to arrive
at a screen with a past, not to exercise the write path the suite already covers.

Usage:
    python3 Tools/seed_history.py [--udid UDID] [--bundle-id ID] [--weeks N] [--wipe]

Defaults to the booted simulator and whichever Hardset build is installed on it. Run the app once
first so the migration and the catalogue seed have happened; this fails loudly rather than
inventing a schema.

Two facts worth not rediscovering:
  * The container path changes on every reinstall. It is re-resolved here every run.
  * GRDB stores dates as UTC `YYYY-MM-DD HH:MM:SS.SSS` text, which is also what the schema's
    `datetime('now','subsec')` default produces. Anything else reads back as a wrong date or nil.
"""

import argparse
import datetime as dt
import os
import random
import sqlite3
import subprocess
import sys
import uuid

DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def stamp(when: dt.datetime) -> str:
    """GRDB's text date encoding: UTC, milliseconds, space-separated."""
    return when.strftime(DATE_FORMAT) + f".{when.microsecond // 1000:03d}"


def new_id() -> str:
    return str(uuid.uuid4()).lower()


def booted_udid() -> str:
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted"],
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if "(Booted)" in line and "(" in line:
            return line.split("(")[1].split(")")[0]
    sys.exit("No booted simulator. Boot one, or pass --udid.")


def installed_bundle_id(udid: str) -> str:
    """Finds the installed Hardset build rather than assuming an identifier.

    The identifier is configurable (`HARDSET_BUNDLE_ID`, because the default may already be
    registered to somebody else), so hardcoding one here sends the seed at a container that does
    not exist and reports it as a missing schema.
    """
    out = subprocess.run(
        ["xcrun", "simctl", "listapps", udid], capture_output=True, text=True, check=True
    ).stdout
    found = sorted(
        {
            line.split('"')[1]
            for line in out.splitlines()
            if "CFBundleIdentifier" in line and "hardset" in line.lower() and '"' in line
        }
    )
    # The widget extension shares the prefix, so prefer the shortest -- the host app.
    apps = [identifier for identifier in found if not identifier.endswith(".widget")]
    if not apps:
        sys.exit(f"No Hardset build installed on {udid}. Build and launch it once first.")
    return min(apps, key=len)


def database_path(udid: str, bundle_id: str) -> str:
    try:
        container = subprocess.run(
            ["xcrun", "simctl", "get_app_container", udid, bundle_id, "data"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        sys.exit(f"{bundle_id} is not installed on {udid}. Build and launch it once first.")

    candidates = []
    for root, _, files in os.walk(container):
        for name in files:
            # The sync metadatabase is a separate store and must never be seeded into.
            if name.endswith((".sqlite", ".db")) and "icloud" not in name.lower():
                candidates.append(os.path.join(root, name))
    if not candidates:
        sys.exit(f"No database under {container}. Launch the app once so it migrates.")
    # The app's own store is the largest; -wal/-shm siblings are excluded by extension.
    return max(candidates, key=os.path.getsize)


# The plan. Four days, so rotation is a real question.
#
# Identified by `catalogSlug`, not display name. Names are user-editable and the catalogue's differ
# from the obvious spelling -- "Bench Press" is `barbell-bench-press`, and seeding by name created a
# second, uncurated movement that the app then honestly reported as "Not attributed". Every muscle
# figure downstream reads from attribution, so seeding past it makes the volume screens unjudgeable.
PLAN = [
    ("Push", ["barbell-bench-press", "overhead-press", "cable-triceps-pushdown", "cable-fly"]),
    ("Pull", ["barbell-row", "lat-pulldown", "seated-cable-row", "barbell-curl"]),
    ("Legs", ["barbell-back-squat", "romanian-deadlift", "leg-press", "lying-leg-curl"]),
    ("Upper", ["incline-barbell-bench-press", "chin-up", "lateral-raise", "face-pull"]),
]

MACHINES = [
    ("Hammer Strength Bench", 2.5),
    ("Cybex Leg Press", 5.0),
    ("Life Fitness Cable Tower", 2.27),
    ("Precor Pulldown", 4.5),
]

# Which machine a movement plausibly happens on, matched on the first keyword found. Round-robin
# assignment was cheaper but produced "Cable Fly · Precor Pulldown", and data that reads as nonsense
# makes every screen harder to judge -- which defeats the point of seeding at all.
MACHINE_FOR_KEYWORD = [
    (("pulldown", "chin", "pull-up", "pullup"), "Precor Pulldown"),
    (("cable", "fly", "pushdown", "face pull", "lateral raise", "curl"), "Life Fitness Cable Tower"),
    (("squat", "leg", "deadlift", "hack"), "Cybex Leg Press"),
    (("bench", "press", "row"), "Hammer Strength Bench"),
]


def machine_for(name: str, machines: dict) -> str:
    lowered = name.lower()
    for keywords, machine_name in MACHINE_FOR_KEYWORD:
        if any(keyword in lowered for keyword in keywords):
            return machines[machine_name]
    return machines["Hammer Strength Bench"]


def resolve_exercise(db, slug):
    """Finds the curated catalogue row for `slug`.

    Fails loudly rather than creating a stand-in. An uncurated movement carries no muscle
    attribution, so the volume report would read "Not attributed" and the seed would be testing the
    app's error copy instead of its arithmetic.
    """
    row = db.execute(
        "SELECT id, name FROM exercises WHERE catalogSlug = ? AND isArchived = 0", (slug,)
    ).fetchone()
    if not row:
        sys.exit(
            f"No catalogue row for {slug!r}. The catalogue changed; update PLAN in this file.\n"
            "List the available slugs with:\n"
            "  sqlite3 <db> \"SELECT catalogSlug FROM exercises WHERE isCurated=1 ORDER BY 1\""
        )
    return row[0], row[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid")
    parser.add_argument(
        "--bundle-id",
        default=os.environ.get("HARDSET_BUNDLE_ID"),
        help="Defaults to whichever Hardset build is installed on the device.",
    )
    parser.add_argument("--weeks", type=int, default=20)
    parser.add_argument("--seed", type=int, default=7, help="RNG seed, so runs are reproducible.")
    parser.add_argument(
        "--wipe", action="store_true",
        help="Delete existing sessions, sets and plans first. Leaves the catalogue alone.",
    )
    parser.add_argument(
        "--second-gym", action="store_true",
        help=(
            "Add a second gym with its own machines, leaving the plan's machines at the first. "
            "Reproduces the cross-gym case: a plan built at one gym, started at another."
        ),
    )
    args = parser.parse_args()

    udid = args.udid or booted_udid()
    bundle_id = args.bundle_id or installed_bundle_id(udid)
    path = database_path(udid, bundle_id)
    print(f"device   {udid}\nbundle   {bundle_id}\ndatabase {path}")

    random.seed(args.seed)
    db = sqlite3.connect(path)
    db.create_function("uuid", 0, new_id)
    db.execute("PRAGMA foreign_keys = ON")

    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for required in ("sessions", "loggedSets", "splits", "splitDays", "splitEntries"):
        if required not in tables:
            sys.exit(f"Table {required!r} is missing. Launch the app once so it migrates.")
    columns = {r[1] for r in db.execute("PRAGMA table_info(sessions)")}
    if "splitDayID" not in columns:
        sys.exit(
            "sessions.splitDayID is missing -- this build predates plan-day attribution.\n"
            "Rebuild the app (DEBUG erases the store on schema change) and launch it once."
        )

    if args.wipe:
        for table in ("loggedSets", "sessionExercises", "sessions", "splitEntries", "splitDays",
                      "splits", "machineExercises", "machines", "gyms"):
            db.execute(f"DELETE FROM {table}")
        print("wiped sessions, plans, gyms and machines")

    now = dt.datetime.now(dt.UTC).replace(microsecond=0)

    gym_id = new_id()
    db.execute(
        "INSERT INTO gyms (id, name, isArchived, createdAt) VALUES (?, ?, 0, ?)",
        (gym_id, "Iron Works", stamp(now - dt.timedelta(weeks=args.weeks + 1))),
    )
    machines = {}
    for name, increment in MACHINES:
        machine_id = new_id()
        db.execute(
            "INSERT INTO machines (id, gymID, name, stackIncrementKg, isArchived, createdAt)"
            " VALUES (?, ?, ?, ?, 0, ?)",
            (machine_id, gym_id, name, increment,
             stamp(now - dt.timedelta(weeks=args.weeks + 1))),
        )
        machines[name] = machine_id

    # A second gym, with its own physically distinct machines. The plan is deliberately left
    # pointing at the first gym's machines: that is the state a lifter is in when they travel, and
    # it is what a plan day started at this gym has to cope with. Machines are never shared between
    # gyms (invariant #10 forbids merging two machines), so these are new rows with empty history.
    if args.second_gym:
        other_gym = new_id()
        db.execute(
            "INSERT INTO gyms (id, name, isArchived, createdAt) VALUES (?, ?, 0, ?)",
            (other_gym, "Downtown Barbell", stamp(now - dt.timedelta(weeks=2))),
        )
        for name, increment in MACHINES:
            db.execute(
                "INSERT INTO machines (id, gymID, name, stackIncrementKg, isArchived, createdAt)"
                " VALUES (?, ?, ?, ?, 0, ?)",
                (new_id(), other_gym, name, increment, stamp(now - dt.timedelta(weeks=2))),
            )
        print("added a second gym (Downtown Barbell) with its own machines")

    # The plan, and one machine bound per movement so the per-machine chart has separate series.
    split_id = new_id()
    db.execute(
        "INSERT INTO splits (id, name, isArchived, createdAt) VALUES (?, ?, 0, ?)",
        (split_id, "Four-day rotation", stamp(now - dt.timedelta(weeks=args.weeks))),
    )
    days = []
    for position, (day_name, movement_names) in enumerate(PLAN):
        day_id = new_id()
        db.execute(
            "INSERT INTO splitDays (id, splitID, name, position, createdAt) VALUES (?, ?, ?, ?, ?)",
            (day_id, split_id, day_name, position, stamp(now - dt.timedelta(weeks=args.weeks))),
        )
        movements = []
        for index, wanted in enumerate(movement_names):
            exercise_id, resolved = resolve_exercise(db, wanted)
            machine_id = machine_for(resolved, machines)
            db.execute(
                "INSERT INTO splitEntries (id, splitDayID, exerciseID, machineID, position,"
                " createdAt) VALUES (?, ?, ?, ?, ?, ?)",
                (new_id(), day_id, exercise_id, machine_id, index,
                 stamp(now - dt.timedelta(weeks=args.weeks))),
            )
            db.execute(
                "INSERT INTO machineExercises (id, machineID, exerciseID, createdAt)"
                " VALUES (?, ?, ?, ?)",
                (new_id(), machine_id, exercise_id,
                 stamp(now - dt.timedelta(weeks=args.weeks))),
            )
            movements.append((exercise_id, resolved, machine_id))
        days.append((day_id, day_name, movements))

    # Opening loads per movement, progressed week over week. Deliberately per (exercise, machine) so
    # the progression chart's per-machine series are each real.
    opening = {}
    for _, _, movements in days:
        for exercise_id, name, machine_id in movements:
            base = 20.0 if any(w in name.lower() for w in ("curl", "raise", "fly", "pull")) else 60.0
            opening[(exercise_id, machine_id)] = base + random.choice([0, 2.5, 5.0])

    sessions = sets_written = 0
    # Trains days in rotation, three per week -- so on a four-day plan the cycle drifts across
    # weekdays exactly as it does in life, and the day that is due is not always the same one.
    rotation = 0
    for week in range(args.weeks, 0, -1):
        for slot, weekday_offset in enumerate((0, 2, 4)):
            day_id, day_name, movements = days[rotation % len(days)]
            rotation += 1

            started = (now - dt.timedelta(weeks=week)
                       + dt.timedelta(days=weekday_offset, hours=random.choice([-2, 0, 1])))
            if started >= now:
                continue
            finished = started + dt.timedelta(minutes=random.randint(48, 74))

            session_id = new_id()
            db.execute(
                "INSERT INTO sessions (id, gymID, title, notes, startedAt, finishedAt, splitDayID)"
                " VALUES (?, ?, ?, '', ?, ?, ?)",
                (session_id, gym_id, day_name, stamp(started), stamp(finished), day_id),
            )
            sessions += 1

            for position, (exercise_id, name, machine_id) in enumerate(movements):
                row_id = new_id()
                db.execute(
                    "INSERT INTO sessionExercises (id, sessionID, exerciseID, machineID, position,"
                    " plannedSets, supersetGroup) VALUES (?, ?, ?, ?, ?, NULL, NULL)",
                    (row_id, session_id, exercise_id, machine_id, position),
                )

                # Double progression: a small load rise every other week, plus real variance.
                elapsed = args.weeks - week
                load = opening[(exercise_id, machine_id)] + 2.5 * (elapsed // 2)
                load += random.choice([-2.5, 0.0, 0.0, 2.5])

                db.execute(
                    "INSERT INTO loggedSets (id, sessionID, exerciseID, machineID,"
                    " sessionExerciseID, setOrdinal, weightKg, reps, rpe, isWarmup, isDropSet,"
                    " completedAt) VALUES (?, ?, ?, ?, ?, 0, ?, ?, NULL, 1, 0, ?)",
                    (new_id(), session_id, exercise_id, machine_id, row_id,
                     round(max(load * 0.5, 10.0), 1), 10,
                     stamp(started + dt.timedelta(minutes=position * 9))),
                )
                sets_written += 1

                for working in range(3):
                    completed = started + dt.timedelta(
                        minutes=position * 9 + 2 + working * 2, seconds=random.randint(0, 50)
                    )
                    db.execute(
                        "INSERT INTO loggedSets (id, sessionID, exerciseID, machineID,"
                        " sessionExerciseID, setOrdinal, weightKg, reps, rpe, isWarmup, isDropSet,"
                        " completedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)",
                        (new_id(), session_id, exercise_id, machine_id, row_id, working + 1,
                         round(load, 1), random.randint(6, 11),
                         random.choice([7.0, 7.5, 8.0, 8.5]), stamp(completed)),
                    )
                    sets_written += 1

    db.commit()
    counts = {
        table: db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        for table in ("sessions", "loggedSets", "splitDays", "machines")
    }
    trained = db.execute(
        "SELECT splitDays.name, MAX(sessions.startedAt) FROM sessions"
        " JOIN splitDays ON splitDays.id = sessions.splitDayID"
        " WHERE sessions.finishedAt IS NOT NULL GROUP BY splitDays.id ORDER BY splitDays.position"
    ).fetchall()
    db.close()

    print(f"\nwrote {sessions} sessions and {sets_written} sets across {args.weeks} weeks")
    print("totals:", ", ".join(f"{k}={v}" for k, v in counts.items()))
    print("last trained per plan day:")
    for name, last in trained:
        print(f"  {name:<8} {last}")
    print("\nRelaunch the app to read against the seeded store.")


if __name__ == "__main__":
    main()
