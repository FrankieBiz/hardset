"""The interaction rules check must pass on the tree as it is, and fail when each rule is broken.

A check that cannot fail is decoration. Each case copies the sources, breaks one rule the way a
drive-by edit would, and asserts the check names it.
"""

import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "Tools/check_interaction_rules.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("check_interaction_rules", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class InteractionRulesTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sources = Path(self.temp.name) / "Sources"
        shutil.copytree(self.tool.SOURCES, self.sources)
        self.tool.SOURCES = self.sources

    def append(self, relative, text):
        path = self.sources / relative
        path.write_text(path.read_text() + "\n" + text + "\n")

    def failures(self):
        return self.tool.run()

    def test_the_tree_as_it_is_passes(self):
        self.assertEqual(self.failures(), [])

    def test_a_success_haptic_under_the_clank_fails(self):
        self.append(
            "HardsetUI/SetRowView.swift",
            "extension SetRowView { func x() -> some View { EmptyView().sensoryFeedback(.success, trigger: 1) } }",
        )
        self.assertTrue(any("success haptic" in f for f in self.failures()))

    def test_a_second_clank_call_fails(self):
        self.append("HardsetUI/SessionView.swift", "func again() { ClankPlayer.shared.play() }")
        self.assertTrue(any("ClankPlayer.shared.play()" in f for f in self.failures()))

    def test_the_stamp_used_elsewhere_fails(self):
        self.append("HardsetUI/RestBarView.swift", "let spring = Tokens.Motion.stamp")
        self.assertTrue(any("Motion.stamp" in f for f in self.failures()))

    def test_the_follow_beat_used_elsewhere_fails(self):
        self.append("HardsetUI/HistoryView.swift", "let x = EmptyView().hardsetArrival(beat: .follow)")
        self.assertTrue(any("follow beat" in f for f in self.failures()))

    def test_a_text_field_in_the_pad_fails(self):
        self.append("HardsetUI/NumericPad.swift", 'let field = TextField("w", text: .constant(""))')
        self.assertTrue(any("system keyboard" in f for f in self.failures()))

    def test_a_text_field_in_the_session_fails(self):
        self.append("HardsetUI/SessionView.swift", "@FocusState private var weightFocused: Bool")
        self.assertTrue(any("system keyboard" in f for f in self.failures()))

    def test_an_accessibility_focus_state_is_not_a_text_input(self):
        self.append("HardsetUI/SessionView.swift", "@AccessibilityFocusState private var focused: Bool")
        self.assertEqual(self.failures(), [])

    def test_a_comment_naming_a_forbidden_thing_is_not_a_use(self):
        self.append("HardsetUI/NumericPad.swift", "// never a TextField( here")
        self.assertEqual(self.failures(), [])

    def test_hard_coded_pad_steps_fail(self):
        self.append("HardsetUI/NumericPad.swift", "let steps = [-5.0, -2.5, 2.5, 5.0]")
        self.assertTrue(any("hard-codes" in f for f in self.failures()))

    def test_a_smaller_key_fails(self):
        path = self.sources / "HardsetUI/DesignTokens.swift"
        text = path.read_text()
        start = text.index("struct HardsetKeyFace")
        end = text.index("minHeight: Tokens.loggerTapTarget", start)
        path.write_text(
            text[:end] + "minHeight: Tokens.minimumTapTarget" + text[end + len("minHeight: Tokens.loggerTapTarget") :]
        )
        self.assertTrue(any("HardsetKeyFace" in f for f in self.failures()))

    def test_a_monument_without_its_worked_from_fails(self):
        path = self.sources / "HardsetUI/VolumeReportView.swift"
        path.write_text(path.read_text().replace("onShowTotalWorking", "onShowSomethingElse"))
        self.assertTrue(any("Worked from hookup" in f for f in self.failures()))

    def test_a_new_monument_in_an_unlisted_file_fails(self):
        self.append("HardsetUI/HistoryView.swift", "let big = Text(\"1\").hardsetText(.monument)")
        self.assertTrue(any("not in MONUMENT_DRAWN_IN" in f for f in self.failures()))

    def test_a_top_pinned_control_in_the_session_fails(self):
        self.append(
            "HardsetUI/SessionView.swift",
            "extension SessionView { func pinned() -> some View { EmptyView().safeAreaInset(edge: .top) { EmptyView() } } }",
        )
        self.assertTrue(any("top of the screen" in f for f in self.failures()))


if __name__ == "__main__":
    unittest.main()
