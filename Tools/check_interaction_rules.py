#!/usr/bin/env python3
"""Hold the interaction rules DESIGN.md states, so a drive-by edit cannot quietly break them.

The log moment is one event: a saved set plays one haptic, the clank, and nothing under it, and the
stamp and the follow beat belong to a set just logged and to nothing else. The type system cannot say
that, so this reads the sources the way `check_figure_cap.py` does, names the few files each rule is
about, and fails with the reason. It is deliberately a text check: a rule that has to be changed on
purpose shows up in the diff where a reviewer will read it, beside the DESIGN.md paragraph that owns
it.

Usage: python3 Tools/check_interaction_rules.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/HardsetKit/Sources"


def read(relative: str) -> str:
    return (SOURCES / relative).read_text()


def strip_comments(text: str) -> str:
    """Drops // comments, so prose that names a forbidden thing is not mistaken for a use of it."""
    return "\n".join(re.sub(r"//.*", "", line) for line in text.splitlines())


def swift_files():
    return sorted(SOURCES.rglob("*.swift"))


def check_one_haptic(failures):
    """The log moment's haptic rule: one haptic, the clank, from the row, once."""
    haptic = strip_comments(read("HardsetUI/Haptic.swift"))
    if re.search(r"\bstatic let success\b", haptic):
        failures.append(
            "Tokens.Haptic declares `success`. A saved set plays the clank and nothing under it; "
            "two patterns on one instant read as a doubled tap. See DESIGN.md, The log moment."
        )

    for path in swift_files():
        code = strip_comments(path.read_text())
        relative = path.relative_to(SOURCES).as_posix()
        if re.search(r"Haptic\.success\b|sensoryFeedback\s*\(\s*\.success", code):
            failures.append(
                f"{relative} plays a success haptic. A saved set plays the clank and nothing "
                "with it (DESIGN.md, The log moment)."
            )

    allowed = {"HardsetUI/SetRowView.swift": 1, "HardsetUI/WelcomeBarView.swift": 1}
    found = {}
    for path in swift_files():
        count = len(re.findall(r"ClankPlayer\.shared\.play\(\)", strip_comments(path.read_text())))
        if count:
            found[path.relative_to(SOURCES).as_posix()] = count
    if found != allowed:
        failures.append(
            f"ClankPlayer.shared.play() is called from {found}, and the rule is {allowed}: once from "
            "the set row's log control and once from the Welcome bar's plate landing. A second call "
            "in the logging path plays the clank twice for one set."
        )

    row = strip_comments(read("HardsetUI/SetRowView.swift"))
    if "LogMoment.isContact(from: old, to: new)" not in row:
        failures.append(
            "SetRowView no longer gates the clank on LogMoment.isContact. The clank belongs to the "
            "frame the row turns logged, which is after the write, and to nothing before it."
        )


def check_stamp_and_follow_scope(failures):
    """Nothing else is allowed to be this theatrical."""
    stamp_allowed = {
        "HardsetUI/DesignTokens.swift",  # defines it
        "HardsetUI/SetRowView.swift",  # the log control's seal
        "HardsetUI/TokenCatalogView.swift",  # names it in words
    }
    follow_allowed = {
        "HardsetCore/LogMoment.swift",  # the plan names the beat
        "HardsetUI/Messages.swift",  # defines the beat parameter
        "HardsetUI/DesignTokens.swift",  # defines Motion.follow
        "HardsetUI/SetRowView.swift",  # the "+1 rep" mark
        "HardsetUI/SessionView.swift",  # the rest bar, the record notice, the hint
        "HardsetUI/TokenCatalogView.swift",
    }
    for path in swift_files():
        code = strip_comments(path.read_text())
        relative = path.relative_to(SOURCES).as_posix()
        if re.search(r"Motion\.stamp\b", code) and relative not in stamp_allowed:
            failures.append(
                f"{relative} uses Motion.stamp. The stamp is the log control's and nothing else's."
            )
        if re.search(r"beat:\s*\.follow|Motion\.follow\b", code) and relative not in follow_allowed:
            failures.append(
                f"{relative} uses the log moment's follow beat. It is for what a set just logged "
                "explains, and a new use is a change to DESIGN.md, The log moment, first."
            )


CHECKS = [
    check_one_haptic,
    check_stamp_and_follow_scope,
]


def run():
    failures = []
    for check in CHECKS:
        check(failures)
    return failures


def main() -> int:
    failures = run()
    if failures:
        print("Interaction rules check failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(f"Interaction rules OK: {len(CHECKS)} rules hold across {len(swift_files())} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
