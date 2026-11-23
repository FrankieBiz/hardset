"""The contrast gate holds the onboarding gauge, and fails when the gauge slips back.

A check that cannot fail is decoration. The gauge's inactive segments are required information
(ruling D22), so each case rewrites the `gaugeTrack` swatch the way a drive-by edit would and
asserts the gate names it, in the appearance where it breaks.
"""

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "Tools/check_contrast.py"
TOKENS = ROOT / "Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift"

GAUGE_TRACK = re.compile(r"public static let gaugeTrack = swatch\([^)]*\)")


def run_gate(tokens_source):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "DesignTokens.swift"
        path.write_text(tokens_source)
        done = subprocess.run(
            [sys.executable, "-I", str(TOOL), str(path)], capture_output=True, text=True
        )
    return done.returncode, done.stdout


def with_track(swatch):
    source = TOKENS.read_text()
    assert GAUGE_TRACK.search(source), "gaugeTrack is not declared as a swatch literal"
    return GAUGE_TRACK.sub(f"public static let gaugeTrack = {swatch}", source)


class GaugeContrastTests(unittest.TestCase):
    def test_the_tree_as_it_is_passes(self):
        code, out = run_gate(TOKENS.read_text())
        self.assertEqual(code, 0, out)

    def test_the_decorative_hairline_as_the_track_fails_in_both_appearances(self):
        # The pair the first-launch gauge drew before ruling D22: 1.54:1 dark, 1.20:1 light.
        code, out = run_gate(with_track("swatch(light: 0xDEDEE4, dark: 0x2E3039)"))
        self.assertEqual(code, 1)
        self.assertIn("gaugeTrack on canvas (dark)", out)
        self.assertIn("gaugeTrack on canvas (light)", out)

    def test_a_track_that_is_loud_under_increase_contrast_fails_the_order(self):
        # `controlEdge`'s own pair clears 3:1 everywhere but, under Increase Contrast, leaves the
        # active segment at about 1.7:1 and 1.6:1 against it: the indicator would be the quieter.
        code, out = run_gate(
            with_track("swatch(light: 0x7E8190, dark: 0x7B7E8C, highLight: 0x595964, highDark: 0x9B9BA5)")
        )
        self.assertEqual(code, 1)
        self.assertNotIn("gaugeTrack on canvas", out)
        self.assertIn("plateBlue on gaugeTrack (dark, increased contrast)", out)
        self.assertIn("plateBlue on gaugeTrack (light, increased contrast)", out)

    def test_a_track_removed_from_the_palette_is_reported_missing(self):
        source = GAUGE_TRACK.sub("", TOKENS.read_text())
        code, out = run_gate(source)
        self.assertEqual(code, 1)
        self.assertIn("gaugeTrack", out)


if __name__ == "__main__":
    unittest.main()
