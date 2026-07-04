import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


PLUGIN_PATH = Path(__file__).resolve().parents[1] / "codex-usage.30s.py"


def load_plugin():
    spec = importlib.util.spec_from_file_location("codex_usage_plugin", PLUGIN_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_jsonl(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            if isinstance(record, str):
                handle.write(record + "\n")
            else:
                handle.write(json.dumps(record) + "\n")


def token_count_event(used_primary=12.0, used_secondary=4.0, timestamp="2026-07-03T04:38:11.000Z"):
    return {
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": 1000,
                    "cached_input_tokens": 250,
                    "output_tokens": 100,
                    "reasoning_output_tokens": 10,
                    "total_tokens": 1100,
                },
                "last_token_usage": {
                    "input_tokens": 100,
                    "cached_input_tokens": 25,
                    "output_tokens": 10,
                    "reasoning_output_tokens": 1,
                    "total_tokens": 110,
                },
                "model_context_window": 902500,
            },
            "rate_limits": {
                "limit_id": "codex",
                "limit_name": None,
                "primary": {
                    "used_percent": used_primary,
                    "window_minutes": 300,
                    "resets_at": 1783070400,
                },
                "secondary": {
                    "used_percent": used_secondary,
                    "window_minutes": 10080,
                    "resets_at": 1783630800,
                },
                "credits": {
                    "has_credits": False,
                    "unlimited": False,
                    "balance": None,
                },
                "plan_type": "plus",
            },
        },
    }


class CodexUsagePluginTest(unittest.TestCase):
    def setUp(self):
        self.plugin = load_plugin()
        self.tempdir = tempfile.TemporaryDirectory()
        self.sessions_dir = Path(self.tempdir.name) / "sessions"

    def tearDown(self):
        self.tempdir.cleanup()

    def test_renders_primary_remaining_in_menu_bar(self):
        session_path = self.sessions_dir / "2026" / "07" / "03" / "rollout.jsonl"
        write_jsonl(session_path, [token_count_event(used_primary=12.0, used_secondary=4.0)])

        output = self.plugin.render_for_swiftbar(self.sessions_dir)

        self.assertTrue(output.startswith("Codex 88%\n---"))
        self.assertIn("---", output)
        self.assertIn("5h remaining: 88%", output)
        self.assertIn("7d remaining: 96%", output)
        self.assertIn("Plan: plus", output)
        self.assertIn("Source: local Codex session logs", output)

    def test_skips_bad_json_and_uses_older_valid_event(self):
        session_path = self.sessions_dir / "2026" / "07" / "03" / "rollout.jsonl"
        write_jsonl(
            session_path,
            [
                token_count_event(used_primary=45.0, used_secondary=10.0),
                "{bad json",
            ],
        )

        output = self.plugin.render_for_swiftbar(self.sessions_dir)

        self.assertTrue(output.startswith("Codex 55%\n---"))
        self.assertIn("5h remaining: 55%", output)

    def test_low_remaining_uses_red_color(self):
        session_path = self.sessions_dir / "2026" / "07" / "03" / "rollout.jsonl"
        write_jsonl(session_path, [token_count_event(used_primary=87.0, used_secondary=60.0)])

        output = self.plugin.render_for_swiftbar(self.sessions_dir)

        self.assertTrue(output.startswith("Codex 13%\n---"))
        self.assertIn("5h remaining: 13%", output)

    def test_missing_sessions_directory_renders_unknown_state(self):
        output = self.plugin.render_for_swiftbar(self.sessions_dir / "missing")

        self.assertTrue(output.startswith("Codex --\n---"))
        self.assertIn("No Codex session directory found", output)

    def test_no_rate_limit_event_renders_explanation(self):
        session_path = self.sessions_dir / "2026" / "07" / "03" / "rollout.jsonl"
        write_jsonl(
            session_path,
            [
                {
                    "timestamp": "2026-07-03T04:38:11.000Z",
                    "type": "event_msg",
                    "payload": {"type": "agent_message", "message": "hello"},
                }
            ],
        )

        output = self.plugin.render_for_swiftbar(self.sessions_dir)

        self.assertTrue(output.startswith("Codex --\n---"))
        self.assertIn("No rate limit event found yet", output)


if __name__ == "__main__":
    unittest.main()
