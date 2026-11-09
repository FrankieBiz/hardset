"""Offline launch-contract tests: never invoke model providers or edit production."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import orchestrate as hub


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(hub, "update_ledger"))
        self.stack.enter_context(patch.object(hub, "get_git_modified_files", return_value=[]))

    def run_worker(self, worker, stdout, **kwargs):
        with patch.object(hub.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout, "")) as run:
            result = worker("Review assigned files", **kwargs)
        return result, run.call_args

    def test_codex_effort_context_and_timeout(self):
        result, call = self.run_worker(hub.dispatch_codex, '{"type":"turn.completed","usage":{}}', timeout_s=37)
        cmd = call.args[0]
        self.assertTrue(result.success)
        self.assertIn('model_reasoning_effort="xhigh"', cmd)
        self.assertIn("CODEX.md", cmd[-1])
        self.assertIn("AGENTS.md", cmd[-1])
        self.assertIn("do not launch other agents, push", cmd[-1].lower())
        self.assertEqual(call.kwargs["timeout"], 37)
        self.assertTrue(call.kwargs["capture_output"])

    def test_explicit_codex_effort(self):
        _, call = self.run_worker(hub.dispatch_codex, "", effort="high")
        self.assertIn('model_reasoning_effort="high"', call.args[0])

    def test_claude_effort_is_applied(self):
        result, call = self.run_worker(hub.dispatch_claude, '{"result":"ok"}', effort="xhigh")
        cmd = call.args[0]
        self.assertTrue(result.success)
        self.assertEqual(cmd[cmd.index("--effort") + 1], "xhigh")

    def test_invalid_effort_never_launches(self):
        with patch.object(hub.subprocess, "run") as run:
            for worker in (hub.dispatch_codex, hub.dispatch_claude):
                with self.assertRaises(ValueError):
                    worker("review", effort="invalid")
            run.assert_not_called()

    def test_failed_verification_fails_all_workers(self):
        for worker, stdout in ((hub.dispatch_codex, ""), (hub.dispatch_claude, '{"result":"ok"}'), (hub.dispatch_opencode, "")):
            with self.subTest(worker=worker.__name__), patch.object(hub, "run_verification", return_value=(False, "failed check")):
                result, _ = self.run_worker(worker, stdout, verify=True)
                self.assertFalse(result.success)
                self.assertNotEqual(result.exit_code, 0)
                self.assertFalse(result.verification_passed)

    def test_timeout_is_reported_as_failure(self):
        for worker in (hub.dispatch_codex, hub.dispatch_claude, hub.dispatch_opencode):
            with self.subTest(worker=worker.__name__), patch.object(hub.subprocess, "run", side_effect=subprocess.TimeoutExpired("worker", 1)):
                result = worker("review", timeout_s=1)
                self.assertFalse(result.success)
                self.assertIn("Execution failed", result.output)

    def test_child_effort_without_model_preserves_argument_positions(self):
        with patch.object(hub.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "{}", "")) as run:
            hub.spawn_child_worktree("codex", "review", "task", effort="xhigh")
        self.assertEqual(run.call_args.args[0][-2:], ["", "xhigh"])

    def test_orca_explicit_binary_wins(self):
        with patch.dict(hub.os.environ, {"ORCA_CLI_COMMAND": "/chosen/orca", "ORCA_DEV_REPO_ROOT": "/dev"}):
            self.assertEqual(hub.resolve_orca(), "/chosen/orca")

    def test_probe_skips_paid_api_by_default(self):
        result = hub.TaskResult("offline", "stub", "stub", "probe", True, 0, 0, "ok")
        with patch.object(hub, "dispatch_codex", return_value=result), patch.object(hub, "dispatch_claude", return_value=result), patch.object(hub, "dispatch_opencode", return_value=result), patch.object(hub, "dispatch_deepseek") as paid, patch.object(hub, "resolve_orca", return_value="/chosen/orca"), patch.object(hub.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "version", "")), contextlib.redirect_stdout(io.StringIO()):
            results = hub.run_probe()
        paid.assert_not_called()
        self.assertEqual(results["deepseek"]["status"], "SKIP")

    def test_workspace_settings(self):
        root = hub.REPO_ROOT
        codex = tomllib.loads((root / ".codex/config.toml").read_text())
        self.assertEqual(codex["model_reasoning_effort"], "xhigh")
        self.assertEqual(codex["plan_mode_reasoning_effort"], "xhigh")
        claude = json.loads((root / ".claude/settings.json").read_text())
        self.assertEqual(claude["effortLevel"], "high")
        self.assertNotIn("model", claude)
        opencode = json.loads((root / "opencode.json").read_text())
        self.assertEqual(opencode["model"], hub.DEFAULT_OPENCODE_MODEL)
        self.assertIn("deepseek", opencode["disabled_providers"])

    def test_cli_forwards_effort_and_fails_when_worker_fails(self):
        result = hub.TaskResult("offline", "stub", "stub", "review", False, 1, 0, "failed")
        for command, dispatcher in (("backend", "dispatch_codex"), ("frontend", "dispatch_claude")):
            with self.subTest(command=command), patch.object(sys, "argv", ["orchestrate.py", command, "--task", "review", "--effort", "xhigh"]), patch.object(hub, dispatcher, return_value=result) as worker, contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    hub.main()
                self.assertEqual(raised.exception.code, 1)
                self.assertEqual(worker.call_args.kwargs["effort"], "xhigh")

    def test_child_helper_passes_defaults_to_selected_orca(self):
        # Run the actual Bash helper against a local fake CLI, without launching agents.
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "orca"
            capture = Path(directory) / "arguments.json"
            fake.write_text(
                f"#!{sys.executable}\n"
                "import json, sys\n"
                "from pathlib import Path\n"
                "if sys.argv[1:] == ['--version']: print('offline-test')\n"
                f"elif sys.argv[1:3] == ['worktree', 'current']: print(json.dumps({{'result': {{'worktree': {{'path': {str(hub.REPO_ROOT)!r}}}}}}}))\n"
                "else:\n"
                f" Path({str(capture)!r}).write_text(json.dumps(sys.argv[1:]))\n"
                " print(json.dumps({'ok': True, 'result': {'worktree': {}}}))\n"
            )
            fake.chmod(0o700)
            env = dict(hub.os.environ, ORCA_CLI_COMMAND=str(fake))
            for agent, model, effort in (("codex", "gpt-6.1-sol", "xhigh"), ("claude", "sonnet", "high"), ("opencode", hub.DEFAULT_OPENCODE_MODEL, None)):
                with self.subTest(agent=agent):
                    proc = subprocess.run(["bash", str(hub.REPO_ROOT / "scripts/orca-child.sh"), "spawn", agent, "offline", "review"], env=env, capture_output=True, text=True)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    args = json.loads(capture.read_text())
                    self.assertEqual(args[args.index("--model") + 1], model)
                    if effort:
                        self.assertEqual(args[args.index("--effort") + 1], effort)
                    else:
                        self.assertNotIn("--effort", args)


if __name__ == "__main__":
    unittest.main()
