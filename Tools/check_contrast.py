#!/usr/bin/env python3
"""Verify the HardsetUI palette against the contrast floors stated in DESIGN.md.

Reads the `swatch(light:dark:highLight:highDark:)` literals out of DesignTokens.swift, so the
numbers checked are the numbers the app renders. Exits non-zero if any text role falls under 7:1
or any control boundary under 3:1 against the surfaces it is drawn on, in any of the four
appearances (light, dark, and each with Increase Contrast).

Usage: python3 Tools/check_contrast.py [path/to/DesignTokens.swift]
"""

import re
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / (
    "Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift"
)

SWATCH = re.compile(
    r"static let (\w+) = swatch\(\s*light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})"
    r"(?:, highLight: 0x([0-9A-Fa-f]{6}), highDark: 0x([0-9A-Fa-f]{6}))?\s*\)"
)
SERIES = re.compile(r"swatch\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)")

# Text and symbol roles: 7:1 (WCAG 2.2 SC 1.4.6) against every listed surface.
SURFACES = ["canvas", "steel", "steelRaised"]
TEXT_ON = {
    "chalk": SURFACES,
    "chalkDim": SURFACES,
    "plateBlue": SURFACES + ["plateBlueSurface"],
    "plateGreen": SURFACES + ["plateGreenSurface"],
    "plateYellow": SURFACES + ["plateYellowSurface"],
    "plateRed": SURFACES + ["plateRedSurface"],
    "warning": SURFACES + ["warningSurface"],
    "onPlateBlue": ["plateBlueFill"],
}
# Body text drawn on the tinted state surfaces.
TINTS = ["plateBlueSurface", "plateGreenSurface", "plateYellowSurface", "plateRedSurface", "warningSurface"]
# Momentary pressed fills: AA (4.5:1) is the floor while a finger is down.
PRESSED = {
    "chalk": ["steelPressed"],
    "chalkDim": ["steelPressed"],
    "onPlateBlue": ["plateBlueFillPressed"],
}
# Boundaries that identify a control: 3:1 (SC 1.4.11).
BOUNDARY_ON = {"controlEdge": SURFACES}


def linear(channel):
    channel /= 255
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def luminance(hex_value):
    r, g, b = (hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def load(path):
    source = path.read_text()
    palette = {}
    for name, light, dark, high_light, high_dark in SWATCH.findall(source):
        light, dark = int(light, 16), int(dark, 16)
        palette[name] = {
            "light": light,
            "dark": dark,
            "light, increased contrast": int(high_light, 16) if high_light else light,
            "dark, increased contrast": int(high_dark, 16) if high_dark else dark,
        }
    series_block = source.split("static let series", 1)
    series = []
    if len(series_block) == 2:
        block = series_block[1].split("]", 1)[0]
        series = [(int(l, 16), int(d, 16)) for l, d in SERIES.findall(block)]
    return palette, series


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    palette, series = load(path)
    required = set(TEXT_ON) | set(BOUNDARY_ON) | set(TINTS) | {"canvas", "steel"}
    missing = sorted(name for name in required if name not in palette)
    if missing:
        print(f"Missing swatches in {path}: {', '.join(missing)}")
        return 1

    failures, checked = [], 0

    def check(fg, bg, floor):
        nonlocal checked
        for appearance in palette[fg]:
            value = ratio(palette[fg][appearance], palette[bg][appearance])
            checked += 1
            if value < floor:
                failures.append(f"{fg} on {bg} ({appearance}): {value:.2f}:1 < {floor}:1")

    for fg, backgrounds in TEXT_ON.items():
        for bg in backgrounds:
            check(fg, bg, 7.0)
    for tint in TINTS:
        for fg in ("chalk", "chalkDim"):
            check(fg, tint, 7.0)
    for fg, backgrounds in PRESSED.items():
        for bg in backgrounds:
            check(fg, bg, 4.5)
    for fg, backgrounds in BOUNDARY_ON.items():
        for bg in backgrounds:
            check(fg, bg, 3.0)
    for index, (light, dark) in enumerate(series):
        for bg in ("canvas", "steel"):
            for value, appearance in ((light, "light"), (dark, "dark")):
                checked += 1
                measured = ratio(value, palette[bg][appearance])
                if measured < 3.0:
                    failures.append(f"series[{index}] on {bg} ({appearance}): {measured:.2f}:1 < 3:1")

    if failures:
        print("\n".join(failures))
        print(f"Contrast: {len(failures)} of {checked} pairs below their floor.")
        return 1
    print(f"Contrast: all {checked} pairs meet their floor across {len(palette)} swatches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
