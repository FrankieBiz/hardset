#!/usr/bin/env python3
"""Hold the interaction rules DESIGN.md states, so a drive-by edit cannot quietly break them.

Three of the app's signatures are interactions, and each is easy to undo without noticing:

1. The log moment. A saved set plays one haptic, the clank, and nothing under it; the stamp and the
   second beat belong to a set just logged and to nothing else.
2. The single-thumb pad traversal. Weight, reps, load steps and corrections are entered on the
   logger's own keypad. A system text field in that path brings up the system keyboard, which is the
   thing the pad exists to prevent. The pad's quick steps come from the machine's own increment, and
   nothing the logger needs is pinned to the top of the screen.
3. The figure scale: every figure drawn at a monument size can be opened to the working behind it,
   and so can every capped estimate: a Progress row's six-week change, the scorecard's biggest gain
   and the live record notice.

The type system cannot say any of this, so this reads the sources the way `check_figure_cap.py`
does, names the few files each rule is about, and fails with the reason. It is deliberately a text
check: a rule that has to be changed on purpose shows up in the diff where a reviewer will read it,
beside the DESIGN.md paragraph that owns it.

Usage: python3 Tools/check_interaction_rules.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/HardsetKit/Sources"

# Files on the logging path: where weight, reps, a load step, a rest or a correction is entered or
# a set is logged. A search field in a picker is text and is not here.
LOGGER_FILES = [
    "HardsetUI/SessionView.swift",
    "HardsetUI/SetRowView.swift",
    "HardsetUI/ExerciseSectionView.swift",
    "HardsetUI/NumericPad.swift",
    "HardsetUI/LoadStepSheet.swift",
    "HardsetUI/SetCorrectionSheet.swift",
    "HardsetUI/RestBarView.swift",
    "HardsetFeature/LiveSessionScreen.swift",
]

# The files the live logger is drawn in, where nothing may be pinned to the top of the screen.
LIVE_SCREEN_FILES = [
    "HardsetUI/SessionView.swift",
    "HardsetUI/SetRowView.swift",
    "HardsetUI/ExerciseSectionView.swift",
    "HardsetUI/RestBarView.swift",
    "HardsetUI/NumericPad.swift",
]

TEXT_INPUT = re.compile(
    r"\bTextField\s*\(|\bTextEditor\s*\(|\bSecureField\s*\(|\.keyboardType\s*\(|"
    r"(?<!Accessibility)FocusState|\.focused\s*\(|\bUITextField\b|\bUITextView\b|\.searchable\s*\("
)
PINNED_TOP = re.compile(r"safeAreaInset\s*\(\s*edge:\s*\.top|\.toolbar\b|\bToolbarItem\b")


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


def check_no_system_keyboard(failures):
    """The single-thumb pad traversal: no text input anywhere on the logging path."""
    for relative in LOGGER_FILES:
        code = strip_comments(read(relative))
        hits = sorted(set(m.group(0).strip() for m in TEXT_INPUT.finditer(code)))
        if hits:
            failures.append(
                f"{relative} uses {', '.join(hits)}. Weight, reps, load steps and corrections are "
                "entered on the logger's own NumericPad; a text input here brings up the system "
                "keyboard and a cursor to place (DESIGN.md, The single-thumb pad traversal)."
            )


def check_pad_steps(failures):
    """The pad's quick steps are the machine's, not a hard-coded 2.5 and 5."""
    pad = strip_comments(read("HardsetUI/NumericPad.swift"))
    if re.search(r"\[\s*-5\.?0?\s*,\s*-2\.5", pad):
        failures.append(
            "NumericPad hard-codes its weight steps. They come from QuickSteps.weight, which uses "
            "the machine's real increment when one is recorded."
        )
    if "QuickSteps.weight(" not in strip_comments(read("HardsetUI/SessionView.swift")):
        failures.append(
            "SessionView no longer passes QuickSteps.weight(machineIncrementKg:unit:) to the "
            "keypad, so the pad would step to loads the machine cannot hold."
        )


def check_step_targets(failures):
    """A chalky thumb: the row's machine steps and every pad key are logger-height cells."""
    row = strip_comments(read("HardsetUI/SetRowView.swift"))
    start = row.find("private func loadAdjustment(")
    body = row[start : start + 1600] if start >= 0 else ""
    if "minHeight: Tokens.loggerTapTarget" not in body:
        failures.append(
            "SetRowView's load steps no longer use Tokens.loggerTapTarget (56 pt) as their height."
        )
    tokens = strip_comments(read("HardsetUI/DesignTokens.swift"))
    key = tokens[tokens.find("struct HardsetKeyFace") :]
    if "minHeight: Tokens.loggerTapTarget" not in key[:2400]:
        failures.append(
            "HardsetKeyFace no longer uses Tokens.loggerTapTarget (56 pt) as its height, so the "
            "pad's keys and quick steps would be smaller than a chalky thumb can hit."
        )


# Where a monument is drawn, and the Worked-from hookup that makes its figure inspectable. A monument
# is a figure drawn at 88 or 72 pt, which is earned only by being a measurement; a measurement a
# lifter cannot open to the sets behind it is exactly what the product refuses.
MONUMENT_DRAWN_IN = {
    "HardsetUI/VolumeReportView.swift": ("onShowTotalWorking", "WorkedFromButton("),
    "HardsetFeature/HardsetRootView.swift": ("WorkedFromButton(", "WorkedFromSheet("),
}
# Files that define or catalogue the monument roles, which draw no figure of their own.
MONUMENT_DEFINITIONS = {
    "HardsetUI/TypeRole.swift",
    "HardsetUI/DesignTokens.swift",
    "HardsetUI/Messages.swift",
    "HardsetUI/TokenCatalogView.swift",
}
MONUMENT_USE = re.compile(r"\.monument\b|\.monumentAside\b|\bmonument:\s*[A-Za-z_]")


def check_monuments_are_inspectable(failures):
    """Every monument opens "Worked from": a new one cannot land without its working."""
    for path in swift_files():
        relative = path.relative_to(SOURCES).as_posix()
        if relative in MONUMENT_DEFINITIONS or relative.endswith("CatalogView.swift"):
            continue
        code = strip_comments(path.read_text())
        if not MONUMENT_USE.search(code):
            continue
        hookups = MONUMENT_DRAWN_IN.get(relative)
        if hookups is None:
            failures.append(
                f"{relative} draws a monument, and is not in MONUMENT_DRAWN_IN. A monument is a "
                "measured figure at 88 or 72 pt and must open Worked from: give it a derivation in "
                "Core (see WorkingSetCountWorking and SessionVolumeWorking), a control that opens "
                "it, and add the file here (DESIGN.md, Inspectable figures)."
            )
        elif not all(hook in code for hook in hookups):
            missing = [hook for hook in hookups if hook not in code]
            failures.append(
                f"{relative} draws a monument and no longer has its Worked from hookup "
                f"({', '.join(missing)}). A large number the lifter cannot open to the sets behind "
                "it is exactly what the product refuses."
            )
    for relative in MONUMENT_DRAWN_IN:
        code = strip_comments(read(relative))
        if not MONUMENT_USE.search(code):
            print(f"note: {relative} no longer draws a monument; it can leave MONUMENT_DRAWN_IN.")


# The capped estimates: a figure no larger than 28 pt that is inferred, not counted. They are held to
# the same rule as a monument, that a number the lifter cannot open to the sets behind it is what the
# product refuses. Each surface draws a control, and the screen that owns it opens the sheet from a
# derivation in Core (ChangeWorking, RecordWorking.liveAccount).
CAPPED_ESTIMATE_HOOKUPS = {
    "HardsetUI/ProgressBoardView.swift": ("onShowChangeWorking", "WorkedFromButton("),
    "HardsetUI/WorkoutReceiptView.swift": ("onExplainGain", "WorkedFromButton("),
    "HardsetUI/SessionView.swift": ("onExplainRecords", "WorkedFromButton("),
    "HardsetFeature/ProgressScreen.swift": ("loadChangeWorking", "WorkedFromSheet("),
    "HardsetFeature/WorkoutReceiptScreen.swift": ("ChangeWorking.lastTime", "WorkedFromSheet("),
    "HardsetFeature/LiveSessionScreen.swift": ("RecordWorking.liveAccount", "WorkedFromSheet("),
}


def check_capped_estimates_are_inspectable(failures):
    """Every capped estimate opens "Worked from": a surface cannot lose its working quietly."""
    for relative, hookups in CAPPED_ESTIMATE_HOOKUPS.items():
        code = strip_comments(read(relative))
        missing = [hook for hook in hookups if hook not in code]
        if missing:
            failures.append(
                f"{relative} no longer has its Worked from hookup ({', '.join(missing)}). It draws a "
                "capped estimate (a six-week change, the scorecard's biggest gain or the live record "
                "notice), and an estimate the lifter cannot open to the sets behind it is exactly "
                "what the product refuses (DESIGN.md, Inspectable figures)."
            )


def check_nothing_pinned_to_the_top(failures):
    """A logger control pinned to the top of the screen is out of reach of one thumb."""
    for relative in LIVE_SCREEN_FILES:
        code = strip_comments(read(relative))
        if PINNED_TOP.search(code):
            failures.append(
                f"{relative} pins something to the top of the screen. The live logger's header "
                "scrolls with its content and everything it pins is at the bottom: the rest bar and "
                "the keypad (DESIGN.md, The single-thumb pad traversal)."
            )


CHECKS = [
    check_one_haptic,
    check_stamp_and_follow_scope,
    check_no_system_keyboard,
    check_pad_steps,
    check_step_targets,
    check_monuments_are_inspectable,
    check_capped_estimates_are_inspectable,
    check_nothing_pinned_to_the_top,
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
