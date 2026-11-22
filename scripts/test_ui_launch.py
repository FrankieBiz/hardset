"""Offline tests for Tools/ui_launch.sh, the launch-retry harness of the native UI job.

They live here because `make check` discovers tests in this directory. The script is run for real, under
the shell options GitHub gives a `run:` step (-e, pipefail), with stub `xcodebuild`, `xcrun` and `sleep`
first on PATH, so what is exercised is the retry and settle logic and nothing about a simulator. That a
real simulator stops refusing the launch is only shown by a macOS run.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "Tools" / "ui_launch.sh"

RUNNER = "com.francisbisignano.hardset.uitests.xctrunner"
APP = "com.francisbisignano.hardset"

# Verbatim from CI run 44796871557 (main, reverse pass): what xcodebuild printed when the runner launch was
# refused before any test of that invocation ran. Both wordings of the refusal are in the one error dump.
RUNNER_DENIAL = '} (error = Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch com.francisbisignano.hardset.uitests.xctrunner." UserInfo={NSLocalizedDescription=Simulator device failed to launch com.francisbisignano.hardset.uitests.xctrunner., NSUnderlyingError=0xb890401e0 {Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "The request to open "com.francisbisignano.hardset.uitests.xctrunner" failed." UserInfo={BSErrorCodeDescription=RequestDenied, NSLocalizedDescription=The request to open "com.francisbisignano.hardset.uitests.xctrunner" failed., NSUnderlyingError=0xb890401b0 {Error Domain=FBSOpenApplicationErrorDomain Code=6 "Application "com.francisbisignano.hardset.uitests.xctrunner" is installing or uninstalling, and cannot be launched." UserInfo={BSErrorCodeDescription=Busy, NSLocalizedFailureReason=Application "com.francisbisignano.hardset.uitests.xctrunner" is installing or uninstalling, and cannot be launched.}}, FBSOpenApplicationRequestID=0x6007, NSLocalizedFailureReason=The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset.uitests.xctrunner" is installing or uninstalling, and cannot be launched").}}, NSLocalizedFailureReason=The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset.uitests.xctrunner" is installing or uninstalling, and cannot be launched")., FBSOpenApplicationRequestID=0x6007, SimCallingSelector=launchApplicationWithID:options:pid:error:, BSErrorCodeDescription=RequestDenied})'
RUNNER_DENIAL_REPORT = '2026-11-20 20:15:17.879 xcodebuild[39466:372752] [MT] IDELaunchReport: c4a5b70e98773300:c4a5b70e98773300: Finished with error: Simulator device failed to launch com.francisbisignano.hardset.uitests.xctrunner.'
RUNNER_DENIAL_SELECTOR = '    SimCallingSelector = "launchApplicationWithID:options:pid:error:";'

BUSY = "\n".join([RUNNER_DENIAL, RUNNER_DENIAL_REPORT, RUNNER_DENIAL_SELECTOR, "** TEST EXECUTE FAILED **"]) + "\n"

# The same refusal reduced to the sentence each wording carries, for the two matching alternatives.
BUSY_SENTENCE_ONLY = f'Application "{RUNNER}" is installing or uninstalling, and cannot be launched.\n'
BUSY_FRONTBOARD_ONLY = (
    f'The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "{RUNNER}" '
    'is installing or uninstalling, and cannot be launched").\n'
)

PASSED = """\
Test Case '-[HardsetUITests.AppScreensUITests testScreensInDarkMode]' started (Iteration 1 of 2).
Test Case '-[HardsetUITests.AppScreensUITests testScreensInDarkMode]' passed (41.200 seconds).
\t Executed 1 test, with 0 failures (0 unexpected) in 41.200 (41.202) seconds
** TEST EXECUTE SUCCEEDED **
"""

ASSERTION_FAILED = """\
Test Case '-[HardsetUITests.AppScreensUITests testScreensInDarkMode]' started (Iteration 1 of 2).
/src/HardsetUITests/AppScreensUITests.swift:88: error: -[HardsetUITests.AppScreensUITests testScreensInDarkMode] : XCTAssertTrue failed
Test Case '-[HardsetUITests.AppScreensUITests testScreensInDarkMode]' failed (12.000 seconds).
\t Executed 1 test, with 1 failure (0 unexpected) in 12.000 (12.002) seconds
** TEST EXECUTE FAILED **
"""

# Run 44210951420: iteration 1 ran five tests and one failed for a real reason, then xcodebuild's own
# retry could not relaunch the runner. A test ran, so this harness leaves it alone.
DENIED_AFTER_FAILURE = "\n".join([
    "Test Case '-[HardsetUITests.AppScreensUITests testGymPickerDark]' started.",
    "Test Case '-[HardsetUITests.AppScreensUITests testGymPickerDark]' passed (27.525 seconds).",
    "Test Case '-[HardsetUITests.AppScreensUITests testOnboardingJourneyDark]' started.",
    "/src/HardsetUITests/AppScreensUITests.swift:336: error: -[HardsetUITests.AppScreensUITests testOnboardingJourneyDark] : Invalid key path isHittable specified in predicate form",
    "Test Case '-[HardsetUITests.AppScreensUITests testOnboardingJourneyDark]' failed (116.855 seconds).",
    "\t Executed 2 tests, with 1 failure (1 unexpected) in 144.380 (144.382) seconds",
    RUNNER_DENIAL,
    RUNNER_DENIAL_REPORT,
    RUNNER_DENIAL_SELECTOR,
    "** TEST EXECUTE FAILED **",
]) + "\n"

# Run 44648846716: the app under test, not the runner, was refused mid-test. That is a test failure, and
# xcodebuild's own -retry-tests-on-failure is what gives it a second iteration.
APP_DENIED_IN_TEST = "\n".join([
    "Test Case '-[HardsetUITests.AppScreensUITests testCorrectionsAndDiscardDark]' started.",
    '} (error = Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch com.francisbisignano.hardset." UserInfo={NSLocalizedDescription=Simulator device failed to launch com.francisbisignano.hardset., NSUnderlyingError=0x7c8e18480 {Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "The request to open "com.francisbisignano.hardset" failed." UserInfo={BSErrorCodeDescription=RequestDenied, NSLocalizedDescription=The request to open "com.francisbisignano.hardset" failed., NSUnderlyingError=0x7c8e189f0 {Error Domain=FBSOpenApplicationErrorDomain Code=6 "Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched." UserInfo={BSErrorCodeDescription=Busy, NSLocalizedFailureReason=Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched.}}, FBSOpenApplicationRequestID=0xf8fc, NSLocalizedFailureReason=The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched").}}, NSLocalizedFailureReason=The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched")., FBSOpenApplicationRequestID=0xf8fc, SimCallingSelector=launchApplicationWithID:options:pid:error:, BSErrorCodeDescription=RequestDenied})',
    '2026-11-20 01:43:56.417 xcodebuild[98412:263010] [MT] IDELaunchReport: 7d5a42e8de1fdfc0:7d5a42e8de1fdfc0: Finished with error: Simulator device failed to launch com.francisbisignano.hardset.',
    '    SimCallingSelector = "launchApplicationWithID:options:pid:error:";',
    '/Users/runner/work/hardset/hardset/HardsetUITests/AppScreensUITests.swift:415: error: -[HardsetUITests.AppScreensUITests testCorrectionsAndDiscardDark] : Failed to get launch progress for <XCUIApplicationImpl: 0x10685c740 com.francisbisignano.hardset at /Users/runner/work/hardset/hardset/dd/Build/Products/Debug-iphonesimulator/Hardset.app>: Simulator device failed to launch com.francisbisignano.hardset. The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched"). (Underlying Error: The request to open "com.francisbisignano.hardset" failed. The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched"). (Underlying Error: The operation couldn’t be completed. Application "com.francisbisignano.hardset" is installing or uninstalling, and cannot be launched.))',
    "Test Case '-[HardsetUITests.AppScreensUITests testCorrectionsAndDiscardDark]' failed (22.441 seconds).",
    "** TEST EXECUTE FAILED **",
]) + "\n"

XCODEBUILD_STUB = """\
#!/bin/bash
# Prints the scripted output for this invocation and exits with its scripted status. Like the real
# xcodebuild, it refuses a -resultBundlePath that already exists and creates one otherwise.
dir="$STUB_DIR"
n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/count"
echo "args: $*" >> "$dir/invocations"
echo "TEST_RUNNER_HARDSET_UI_SHOT_DIR=${TEST_RUNNER_HARDSET_UI_SHOT_DIR:-}" >> "$dir/env"
prev=""
for arg in "$@"; do
  if [ "$prev" = "-resultBundlePath" ]; then
    if [ -e "$arg" ]; then
      echo "xcodebuild: error: Existing file at -resultBundlePath \\"$arg\\""
      exit 70
    fi
    mkdir -p "$arg"
  fi
  prev=$arg
done
if [ -f "$dir/out.$n" ]; then cat "$dir/out.$n"; fi
exit "$(cat "$dir/rc.$n" 2>/dev/null || echo 0)"
"""

XCRUN_STUB = """\
#!/bin/bash
# Answers the two simctl queries the script makes. STUB_BOOTED=0 makes the device read as shut down.
# STUB_CONTAINERS is a comma separated list consumed one entry per get_app_container call, the last
# repeating; an entry of - is "not installed".
dir="$STUB_DIR"
if [ "$1 $2 $3" = "simctl list devices" ]; then
  echo "== Devices =="
  echo "-- iOS 26.0 --"
  echo "    iPhone 17 Pro ($STUB_OTHER_UDID) (Booted)"
  if [ "${STUB_BOOTED:-1}" = 1 ]; then
    echo "    iPhone 17 ($STUB_UDID) (Booted)"
  else
    echo "    iPhone 17 ($STUB_UDID) (Shutdown)"
  fi
  exit 0
fi
if [ "$1" = simctl ] && [ "$2" = get_app_container ]; then
  n=$(( $(cat "$dir/containers.n" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$dir/containers.n"
  IFS=, read -r -a seq <<< "${STUB_CONTAINERS:--}"
  i=$(( n - 1 ))
  if [ "$i" -ge "${#seq[@]}" ]; then i=$(( ${#seq[@]} - 1 )); fi
  entry=${seq[$i]}
  if [ "$entry" = "-" ]; then exit 2; fi
  echo "$entry"
  exit 0
fi
echo "unexpected xcrun call: $*" >&2
exit 99
"""

SLEEP_STUB = """\
#!/bin/bash
echo "$1" >> "$STUB_DIR/sleeps"
"""


class Harness(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.stubs = self.root / "stubs"
        self.stubs.mkdir()
        self.work = self.root / "work"
        self.work.mkdir()
        for name, body in (("xcodebuild", XCODEBUILD_STUB), ("xcrun", XCRUN_STUB), ("sleep", SLEEP_STUB)):
            path = self.stubs / name
            path.write_text(body)
            path.chmod(0o755)
        self.outputs = []

    def script_xcodebuild(self, *attempts):
        """Each attempt is (output, exit status), consumed by successive xcodebuild invocations."""
        for n, (output, rc) in enumerate(attempts, start=1):
            (self.stubs / f"out.{n}").write_text(output)
            (self.stubs / f"rc.{n}").write_text(str(rc))

    def run_step(self, body, env=None):
        """Run `body` after sourcing the script, as a workflow step would, from the work directory."""
        environment = {
            **os.environ,
            "PATH": f"{self.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(self.stubs),
            "STUB_UDID": "AAAA-1111",
            "STUB_OTHER_UDID": "BBBB-2222",
            # Fast and deterministic: sleep is stubbed, so these only bound the loops.
            "UI_SETTLE_TIMEOUT": "30",
            "UI_SETTLE_POLL": "3",
        }
        environment.update(env or {})
        return subprocess.run(
            ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", f". '{SCRIPT}'\n{body}"],
            cwd=self.work,
            env=environment,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def stub_lines(self, name):
        path = self.stubs / name
        return path.read_text().splitlines() if path.exists() else []

    def invocations(self):
        return len(self.stub_lines("invocations"))

    def sleeps_for_backoff(self):
        # The settle loop also sleeps (3 seconds); the retry backoff is every other value.
        return [s for s in self.stub_lines("sleeps") if s != "3"]


class RetryTests(Harness):
    DARK = (
        'ui_xcodebuild "dark pass" ui-test.log test-without-building -only-testing:HardsetUITests '
        "-resultBundlePath app-screens/ui-dark.xcresult || echo \"status=$?\""
    )

    def setUp(self):
        super().setUp()
        (self.work / "app-screens").mkdir()

    def test_clean_run_is_one_attempt_with_no_retry_line(self):
        self.script_xcodebuild((PASSED, 0))
        result = self.run_step('ui_xcodebuild "dark pass" ui-test.log test-without-building -resultBundlePath app-screens/ui-dark.xcresult')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.invocations(), 1)
        self.assertNotIn("launch denied", result.stdout)
        self.assertEqual(self.sleeps_for_backoff(), [])
        self.assertIn("TEST EXECUTE SUCCEEDED", (self.work / "ui-test.log").read_text())
        self.assertIn("** TEST EXECUTE SUCCEEDED **", result.stdout)

    def test_busy_then_success_retries_once_and_says_so_in_one_line(self):
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertNotIn("status=", result.stdout, result.stdout + result.stderr)
        self.assertEqual(self.invocations(), 2)
        retry_lines = [l for l in result.stdout.splitlines() if "launch denied on attempt" in l]
        self.assertEqual(len(retry_lines), 1, result.stdout)
        self.assertIn("dark pass", retry_lines[0])
        self.assertIn("attempt 1 of 3", retry_lines[0])
        self.assertEqual(self.sleeps_for_backoff(), ["20"])
        # The denial itself is visible in the job log, and both attempts are in the file.
        self.assertIn("is installing or uninstalling, and cannot be launched", result.stdout)
        self.assertIn("Simulator device failed to launch com.francisbisignano.hardset.uitests.xctrunner", result.stdout)
        log = (self.work / "ui-test.log").read_text()
        self.assertIn("is installing or uninstalling", log)
        self.assertIn("TEST EXECUTE SUCCEEDED", log)
        self.assertIn("launch denied on attempt 1 of 3", log)
        self.assertLess(log.index("is installing or uninstalling"), log.index("TEST EXECUTE SUCCEEDED"))

    def test_denied_attempt_result_bundle_is_kept_aside_so_the_retry_can_write_its_own(self):
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        self.run_step(self.DARK)
        # The stub, like xcodebuild, fails the retry if the first bundle were still in the way.
        self.assertTrue((self.work / "app-screens" / "ui-dark.attempt1.xcresult").is_dir())
        self.assertTrue((self.work / "app-screens" / "ui-dark.xcresult").is_dir())
        self.assertEqual(self.invocations(), 2)
        self.assertNotIn("Existing file", (self.work / "ui-test.log").read_text())

    def test_either_wording_of_the_refusal_is_enough_to_retry(self):
        for fixture in (BUSY_SENTENCE_ONLY, BUSY_FRONTBOARD_ONLY):
            with self.subTest(fixture=fixture[:40]):
                for leftover in self.stubs.glob("*"):
                    if leftover.name not in ("xcodebuild", "xcrun", "sleep"):
                        leftover.unlink()
                shutil.rmtree(self.work / "app-screens", ignore_errors=True)
                (self.work / "app-screens").mkdir()
                self.script_xcodebuild((fixture + "** TEST EXECUTE FAILED **\n", 65), (PASSED, 0))
                result = self.run_step(self.DARK)
                self.assertNotIn("status=", result.stdout)
                self.assertEqual(self.invocations(), 2)

    def test_denied_every_time_stops_at_three_attempts_and_fails_with_the_message_unchanged(self):
        self.script_xcodebuild((BUSY, 65), (BUSY, 65), (BUSY, 65), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertIn("status=65", result.stdout, result.stdout + result.stderr)
        self.assertEqual(self.invocations(), 3)
        self.assertEqual(self.sleeps_for_backoff(), ["20", "40"])
        retry_lines = [l for l in result.stdout.splitlines() if "launching again" in l]
        self.assertEqual(len(retry_lines), 2)
        self.assertIn("attempt 2 of 3", retry_lines[1])
        self.assertIn("giving up", result.stdout)
        log = (self.work / "ui-test.log").read_text()
        self.assertEqual(log.count(RUNNER_DENIAL), 3)
        self.assertNotIn("TEST EXECUTE SUCCEEDED", log)

    def test_assertion_failure_is_never_retried(self):
        self.script_xcodebuild((ASSERTION_FAILED, 65), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertIn("status=65", result.stdout)
        self.assertEqual(self.invocations(), 1)
        self.assertEqual(self.sleeps_for_backoff(), [])
        self.assertNotIn("TEST EXECUTE SUCCEEDED", (self.work / "ui-test.log").read_text())

    def test_a_denial_after_a_test_started_is_not_retried(self):
        # Both shapes seen in CI: xcodebuild's own iteration-2 relaunch refused after a real failure
        # (44210951420), and the app under test refused inside a test (44648846716).
        for name, fixture in (("after a failure", DENIED_AFTER_FAILURE), ("app in a test", APP_DENIED_IN_TEST)):
            with self.subTest(name):
                for leftover in self.stubs.glob("*"):
                    if leftover.name not in ("xcodebuild", "xcrun", "sleep"):
                        leftover.unlink()
                shutil.rmtree(self.work / "app-screens", ignore_errors=True)
                (self.work / "app-screens").mkdir()
                self.script_xcodebuild((fixture, 65), (PASSED, 0))
                result = self.run_step(self.DARK)
                self.assertIn("status=65", result.stdout)
                self.assertEqual(self.invocations(), 1)
                self.assertNotIn("launch denied on attempt", result.stdout)

    def test_a_run_that_exited_zero_is_never_retried(self):
        # Denial text in the log of a run that succeeded as far as xcodebuild is concerned.
        self.script_xcodebuild((BUSY, 0), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertNotIn("status=", result.stdout)
        self.assertEqual(self.invocations(), 1)

    def test_failure_with_no_denial_is_not_retried(self):
        self.script_xcodebuild(("error: The build failed\n** TEST FAILED **\n", 65), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertIn("status=65", result.stdout)
        self.assertEqual(self.invocations(), 1)

    def test_an_assertion_failure_after_a_denied_launch_is_still_a_failure(self):
        self.script_xcodebuild((BUSY, 65), (ASSERTION_FAILED, 65), (PASSED, 0))
        result = self.run_step(self.DARK)
        self.assertIn("status=65", result.stdout)
        self.assertEqual(self.invocations(), 2)
        self.assertNotIn("TEST EXECUTE SUCCEEDED", (self.work / "ui-test.log").read_text())

    def test_attempt_limit_and_backoff_are_configurable(self):
        self.script_xcodebuild((BUSY, 65), (BUSY, 65), (BUSY, 65), (BUSY, 65), (PASSED, 0))
        result = self.run_step(self.DARK, env={"UI_LAUNCH_ATTEMPTS": "2", "UI_LAUNCH_BACKOFF": "7"})
        self.assertIn("status=65", result.stdout)
        self.assertEqual(self.invocations(), 2)
        self.assertEqual(self.sleeps_for_backoff(), ["7"])

    def test_caller_environment_reaches_every_attempt(self):
        # The reverse-order loop sets TEST_RUNNER_HARDSET_UI_SHOT_DIR by prefixing the call.
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        self.run_step(
            'TEST_RUNNER_HARDSET_UI_SHOT_DIR=/shots ui_xcodebuild "testX" t.log test-without-building '
            "-resultBundlePath app-screens/t.xcresult"
        )
        self.assertEqual(self.stub_lines("env"), ["TEST_RUNNER_HARDSET_UI_SHOT_DIR=/shots"] * 2)

    def test_log_is_started_fresh_for_each_invocation(self):
        (self.work / "t.log").write_text("left over from an earlier pass\n")
        self.script_xcodebuild((PASSED, 0))
        self.run_step('ui_xcodebuild "t" t.log test-without-building')
        self.assertNotIn("left over", (self.work / "t.log").read_text())

    def test_a_caller_without_errexit_keeps_it_off(self):
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        result = self.run_step('set +e; ui_xcodebuild "t" t.log test-without-building; echo "errexit=$-"')
        self.assertIn("errexit=", result.stdout)
        self.assertNotIn("e", result.stdout.split("errexit=")[1].split()[0])

    def test_a_caller_with_errexit_gets_it_back(self):
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        result = self.run_step('ui_xcodebuild "t" t.log test-without-building; echo "flags=$-"')
        self.assertIn("e", result.stdout.split("flags=")[1].split()[0])


class SettleTests(Harness):
    WATCH = {"UI_SIM_UDID": "AAAA-1111", "UI_SIM_BUNDLES": f"{APP} {RUNNER}"}

    def test_stable_device_settles_after_the_required_looks(self):
        result = self.run_step("ui_settle_simulator", env={**self.WATCH, "STUB_CONTAINERS": "/c/app1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Simulator settled after 6s", result.stdout)
        self.assertIn(f"{APP}=installed", result.stdout)
        self.assertEqual(self.stub_lines("sleeps"), ["3", "3"])

    def test_install_that_is_still_changing_is_waited_out(self):
        # Two bundles are probed per look, so the container paths change look by look through the
        # fourth and then hold: looks five and six match their predecessor, and the sixth settles it.
        paths = ",".join(["/c/1", "/c/1", "/c/2", "/c/2", "/c/3", "/c/3", "/c/4", "/c/4"])
        result = self.run_step("ui_settle_simulator", env={**self.WATCH, "STUB_CONTAINERS": paths})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Simulator settled after 15s", result.stdout)
        self.assertEqual(self.stub_lines("sleeps"), ["3"] * 5)

    def test_a_bundle_that_stays_absent_is_settled(self):
        result = self.run_step("ui_settle_simulator", env={**self.WATCH, "STUB_CONTAINERS": "-"})
        self.assertIn("Simulator settled after 6s", result.stdout)
        self.assertIn(f"{RUNNER}=absent", result.stdout)

    def test_a_device_that_is_not_booted_times_out_and_carries_on(self):
        result = self.run_step(
            "ui_settle_simulator; echo returned=$?",
            env={**self.WATCH, "STUB_BOOTED": "0", "UI_SETTLE_TIMEOUT": "9"},
        )
        self.assertIn("Simulator did not settle within 9s", result.stdout)
        self.assertIn("not-booted", result.stdout)
        self.assertIn("returned=0", result.stdout)

    def test_only_the_device_asked_about_counts_as_booted(self):
        # The stub lists another booted device; the watched one is shut down.
        result = self.run_step(
            "ui_settle_simulator",
            env={**self.WATCH, "STUB_BOOTED": "0", "UI_SETTLE_TIMEOUT": "3"},
        )
        self.assertIn("did not settle", result.stdout)

    def test_without_a_device_it_does_nothing(self):
        result = self.run_step("ui_settle_simulator; echo done", env={"UI_SIM_UDID": ""})
        self.assertEqual(result.stdout.strip(), "done")
        self.assertEqual(self.stub_lines("sleeps"), [])

    def test_every_invocation_settles_before_it_launches_and_again_before_a_retry(self):
        self.script_xcodebuild((BUSY, 65), (PASSED, 0))
        result = self.run_step(
            'ui_xcodebuild "t" t.log test-without-building',
            env={**self.WATCH, "STUB_CONTAINERS": "/c/1"},
        )
        self.assertEqual(result.stdout.count("Simulator settled"), 2, result.stdout)
        self.assertLess(result.stdout.index("Simulator settled"), result.stdout.index("launch denied"))


class WorkflowWiringTests(unittest.TestCase):
    """The step must keep using the harness for every xcodebuild that launches the runner."""

    def setUp(self):
        self.workflow = (Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ios-ui.yml").read_text()

    def test_every_test_without_building_goes_through_the_harness(self):
        for line in self.workflow.splitlines():
            if "test-without-building" in line and not line.lstrip().startswith("#"):
                self.assertIn("ui_xcodebuild", line, line)

    def test_the_harness_is_sourced_and_the_reverse_pass_and_timeout_remain(self):
        self.assertIn(". Tools/ui_launch.sh", self.workflow)
        self.assertIn("in reverse of their normal order", self.workflow)
        self.assertIn("timeout-minutes: 180", self.workflow)
        self.assertNotIn("XCTExpectFailure", self.workflow)


class FinalGateTests(unittest.TestCase):
    """The last lines of the step decide the job. Run them as they are written, under `bash -e`."""

    def gate_script(self):
        lines = (Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ios-ui.yml").read_text().splitlines()
        start = next(i for i, line in enumerate(lines) if line.strip() == "PASSES_FAILED=0")
        block = []
        for line in lines[start:]:
            if not line.startswith("          "):
                break
            block.append(line[10:])
        return "\n".join(block)

    def run_gate(self, dark, light, reverse_failed):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "ui-test.log").write_text(dark)
            (Path(tmp) / "ui-test-light.log").write_text(light)
            return subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-c", f"REVERSE_FAILED={reverse_failed}\n{self.gate_script()}"],
                cwd=tmp,
                capture_output=True,
                text=True,
                timeout=30,
            )

    def test_everything_green_passes(self):
        self.assertEqual(self.run_gate(PASSED, PASSED, 0).returncode, 0)

    def test_a_dark_pass_that_never_succeeded_fails_the_job_even_with_a_green_reverse_pass(self):
        # The case the old `a && b` line let through: the first grep failed and nothing stopped.
        result = self.run_gate(BUSY, PASSED, 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Dark pass failed", result.stdout)

    def test_a_dark_pass_that_failed_an_assertion_fails_the_job(self):
        self.assertNotEqual(self.run_gate(ASSERTION_FAILED, PASSED, 0).returncode, 0)

    def test_a_light_pass_that_never_succeeded_fails_the_job(self):
        result = self.run_gate(PASSED, BUSY, 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Light pass failed", result.stdout)

    def test_a_failed_reverse_pass_fails_the_job(self):
        self.assertNotEqual(self.run_gate(PASSED, PASSED, 1).returncode, 0)

    def test_both_passes_are_reported_when_both_failed(self):
        result = self.run_gate(BUSY, BUSY, 0)
        self.assertIn("Dark pass failed", result.stdout)
        self.assertIn("Light pass failed", result.stdout)


if __name__ == "__main__":
    unittest.main()
