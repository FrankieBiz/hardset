#!/usr/bin/env python3
"""Hold the figure scale's rule: size is earned by being a measurement.

DESIGN.md states it. A number the lifter typed or the app counted may be set at `figureXL` (44 pt),
`countdown` (64 pt), or a monument (`monument` 88 pt, `monumentAside` 72 pt). An estimate, whatever formula produced it, is never drawn
larger than `readout` (28 pt, `Tokens.Text.estimateCeiling`). The type system cannot say which
numbers are estimates, so this check says where the large roles may appear: only in the files below,
each of which draws measurements and nothing else at that size. A new use of a large role in any
other file fails the build until the file is added here with its reason, which puts the question,
"is this number a measurement?", in the diff where a reviewer will read it.

It also pins the ceiling itself, so the rule cannot be loosened by editing one constant unnoticed.

Usage: python3 Tools/check_figure_cap.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/HardsetKit/Sources"
TOKENS = SOURCES / "HardsetUI/DesignTokens.swift"

CEILING = 28

# A role named at a call site or in a switch: `.monument`, `.monumentAside`, `.figureXL`,
# `.countdown`, and `.hero`,
# the 34 pt role that is also above the ceiling. The declarations (`static let figureXL`,
# `case figureXL`) have no leading dot and are not matched.
LARGE_ROLE = re.compile(r"\.(monumentAside|monument|figureXL|countdown|hero)\b")

# Where a large role may be named, and why each use is a measurement. Paths are relative to the
# Sources directory.
ALLOWED = {
    "HardsetUI/TypeRole.swift": "defines the roles",
    "HardsetUI/Messages.swift": (
        "StatLedger: counts and sums of logged sets; an item marked isEstimate is drawn at readout"
    ),
    "HardsetUI/SetRowView.swift": "weight and reps the lifter typed",
    "HardsetUI/WorkoutReceiptView.swift": "the load and reps of each recorded set",
    "HardsetUI/VolumeReportView.swift": (
        "the exact count of working sets in the window; per-muscle credits stay small"
    ),
    "HardsetUI/RestBarView.swift": "the countdown to a deadline the lifter chose",
    "HardsetUI/TokenCatalogView.swift": "the catalogue names each role to show it",
    "HardsetUI/NumericPad.swift": "the value the lifter is typing (hero)",
    "HardsetUI/WelcomeBarView.swift": "the total of the plates the lifter loaded (hero)",
}


def strip_comments(text: str) -> str:
    """Drops // comments, so prose that names a role is not mistaken for a use of it."""
    return "\n".join(re.sub(r"//.*", "", line) for line in text.splitlines())


def main() -> int:
    failures = []

    tokens = TOKENS.read_text()
    ceiling = re.search(r"static let estimateCeiling: CGFloat = (\d+)", tokens)
    if not ceiling or int(ceiling.group(1)) != CEILING:
        found = ceiling.group(1) if ceiling else "missing"
        failures.append(
            f"Tokens.Text.estimateCeiling is {found}, and DESIGN.md says {CEILING}. "
            "Raising it lets an estimate be set larger than a readout."
        )

    used = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        relative = path.relative_to(SOURCES).as_posix()
        hits = sorted(set(LARGE_ROLE.findall(strip_comments(path.read_text()))))
        if hits:
            used[relative] = hits

    for relative, roles in used.items():
        if relative not in ALLOWED:
            failures.append(
                f"{relative} uses {', '.join('.' + r for r in roles)}. Those roles are for "
                "measurements. If every number it draws at that size is one the lifter typed or the "
                "app counted, add the file to ALLOWED in Tools/check_figure_cap.py with the reason; "
                "if any is an estimate, draw it at .readout."
            )

    stale = sorted(set(ALLOWED) - set(used))
    for relative in stale:
        print(f"note: {relative} no longer names a large role; it can leave ALLOWED.")

    if failures:
        print("Figure scale check failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(
        f"Figure scale OK: estimate ceiling {CEILING} pt; large roles named in "
        f"{len(used)} files, all allowed."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
