# Codex Usage Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftBar plugin that shows the latest locally reported Codex rate-limit remaining percentage in the macOS menu bar.

**Architecture:** The implementation is one executable Python SwiftBar plugin script with pure parser and renderer functions inside the same file. It reads `~/.codex/sessions/**/*.jsonl`, finds the newest `event_msg` `token_count` event with `rate_limits`, calculates remaining percentages, and prints SwiftBar-compatible menu output. The project also includes install documentation and a focused standard-library verification file for the parser and renderer behavior.

**Tech Stack:** Python 3 standard library, SwiftBar plugin text protocol, Git.

---

## Scope Check

The spec covers one subsystem: a local SwiftBar plugin for Codex rate-limit display. No decomposition into separate plans is needed.

## File Structure

- Create `.gitignore`
  - Ignores macOS metadata and Python bytecode/cache files.
- Create `codex-usage.30s.py`
  - The only runtime plugin script. Contains session discovery, JSONL parsing, formatting, and SwiftBar rendering.
- Create `tests/test_codex_usage_plugin.py`
  - Focused verification for parser and renderer behavior using Python `unittest` and temporary fixture directories.
- Create `README.md`
  - Installation, security boundary, usage, and manual SwiftBar verification steps.
- Existing `docs/superpowers/specs/2026-07-03-codex-usage-menubar-design.md`
  - Design source of truth. Do not modify unless requirements change.

## Task 1: Project Hygiene

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.DS_Store
**/.DS_Store
__pycache__/
*.py[cod]
.pytest_cache/
.coverage
htmlcov/
```

- [ ] **Step 2: Verify ignored macOS metadata is no longer shown**

Run:

```bash
git status --short
```

Expected output includes only tracked-plan context and `.gitignore` as untracked or modified work. It must not list `.DS_Store` files.

- [ ] **Step 3: Commit project hygiene**

```bash
git add .gitignore
git commit -m "chore: add project ignore rules"
```

Expected output contains:

```text
[feat-swiftbar-codex-usage
```

## Task 2: Add Focused Verification File

**Files:**
- Create: `tests/test_codex_usage_plugin.py`

- [ ] **Step 1: Create the verification file**

```python
import importlib.util
import json
import os
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

        self.assertTrue(output.startswith("Codex 88% | color=#16823A"))
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

        self.assertTrue(output.startswith("Codex 55% | color=#16823A"))
        self.assertIn("5h remaining: 55%", output)

    def test_low_remaining_uses_red_color(self):
        session_path = self.sessions_dir / "2026" / "07" / "03" / "rollout.jsonl"
        write_jsonl(session_path, [token_count_event(used_primary=87.0, used_secondary=60.0)])

        output = self.plugin.render_for_swiftbar(self.sessions_dir)

        self.assertTrue(output.startswith("Codex 13% | color=#D92D20"))
        self.assertIn("5h remaining: 13%", output)

    def test_missing_sessions_directory_renders_unknown_state(self):
        output = self.plugin.render_for_swiftbar(self.sessions_dir / "missing")

        self.assertTrue(output.startswith("Codex -- | color=#8E8E93"))
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

        self.assertTrue(output.startswith("Codex -- | color=#8E8E93"))
        self.assertIn("No rate limit event found yet", output)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run verification to confirm it fails before the plugin exists**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output contains an import error or file-not-found error for `codex-usage.30s.py`.

- [ ] **Step 3: Commit the verification file**

```bash
git add tests/test_codex_usage_plugin.py
git commit -m "test: add codex usage plugin verification"
```

Expected output contains:

```text
[feat-swiftbar-codex-usage
```

## Task 3: Implement the SwiftBar Plugin

**Files:**
- Create: `codex-usage.30s.py`

- [ ] **Step 1: Create `codex-usage.30s.py`**

```python
#!/usr/bin/env python3
"""SwiftBar plugin for locally reported Codex rate-limit usage."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional, Sequence, Tuple, Union


DEFAULT_SESSIONS_DIR = Path.home() / ".codex" / "sessions"

COLOR_GREEN = "#16823A"
COLOR_YELLOW = "#B7791F"
COLOR_RED = "#D92D20"
COLOR_GRAY = "#8E8E93"


@dataclass(frozen=True)
class WindowUsage:
    label: str
    used_percent: Optional[float]
    remaining_percent: Optional[int]
    resets_at: Optional[float]


@dataclass(frozen=True)
class UsageSnapshot:
    primary: Optional[WindowUsage]
    secondary: Optional[WindowUsage]
    plan_type: Optional[str]
    credits: Any
    reported_at: Optional[datetime]
    source_path: Path


@dataclass(frozen=True)
class UsageError:
    menu_value: str
    message: str
    color: str = COLOR_GRAY
    detail: Optional[str] = None


def number_or_none(value: Any) -> Optional[float]:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def remaining_from_used(used_percent: Optional[float]) -> Optional[int]:
    if used_percent is None:
        return None
    remaining = 100.0 - used_percent
    bounded = min(100.0, max(0.0, remaining))
    return int(round(bounded))


def format_window_label(window_minutes: Any) -> str:
    minutes = number_or_none(window_minutes)
    if minutes is None:
        return "--"
    whole_minutes = int(minutes)
    if whole_minutes % 1440 == 0:
        return f"{whole_minutes // 1440}d"
    if whole_minutes % 60 == 0:
        return f"{whole_minutes // 60}h"
    return f"{whole_minutes}m"


def parse_window(raw: Any) -> Optional[WindowUsage]:
    if not isinstance(raw, dict):
        return None
    used_percent = number_or_none(raw.get("used_percent"))
    return WindowUsage(
        label=format_window_label(raw.get("window_minutes")),
        used_percent=used_percent,
        remaining_percent=remaining_from_used(used_percent),
        resets_at=number_or_none(raw.get("resets_at")),
    )


def parse_timestamp(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone()


def parse_snapshot(record: Any, source_path: Path) -> Optional[UsageSnapshot]:
    if not isinstance(record, dict):
        return None
    if record.get("type") != "event_msg":
        return None
    payload = record.get("payload")
    if not isinstance(payload, dict) or payload.get("type") != "token_count":
        return None
    rate_limits = payload.get("rate_limits")
    if not isinstance(rate_limits, dict):
        return None

    primary = parse_window(rate_limits.get("primary"))
    secondary = parse_window(rate_limits.get("secondary"))
    if primary is None and secondary is None:
        return None

    plan_type = rate_limits.get("plan_type")
    if not isinstance(plan_type, str):
        plan_type = None

    return UsageSnapshot(
        primary=primary,
        secondary=secondary,
        plan_type=plan_type,
        credits=rate_limits.get("credits"),
        reported_at=parse_timestamp(record.get("timestamp")),
        source_path=source_path,
    )


def discover_session_files(sessions_dir: Path) -> List[Path]:
    candidates: List[Tuple[float, Path]] = []
    for path in sessions_dir.rglob("*.jsonl"):
        try:
            candidates.append((path.stat().st_mtime, path))
        except OSError:
            continue
    candidates.sort(key=lambda item: item[0], reverse=True)
    return [path for _, path in candidates]


def read_latest_snapshot_from_file(path: Path) -> Optional[UsageSnapshot]:
    text = path.read_text(encoding="utf-8", errors="replace")
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            record = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        snapshot = parse_snapshot(record, path)
        if snapshot is not None:
            return snapshot
    return None


def find_latest_snapshot(sessions_dir: Path) -> Union[UsageSnapshot, UsageError]:
    if not sessions_dir.exists() or not sessions_dir.is_dir():
        return UsageError(
            menu_value="--",
            message="No Codex session directory found",
            detail=str(sessions_dir),
        )

    try:
        files = discover_session_files(sessions_dir)
    except OSError as exc:
        return UsageError(
            menu_value="!",
            message="Unable to read Codex session logs",
            color=COLOR_RED,
            detail=f"{type(exc).__name__}: {exc}",
        )

    first_read_error: Optional[str] = None
    for path in files:
        try:
            snapshot = read_latest_snapshot_from_file(path)
        except OSError as exc:
            if first_read_error is None:
                first_read_error = f"{path}: {type(exc).__name__}: {exc}"
            continue
        if snapshot is not None:
            return snapshot

    if first_read_error is not None:
        return UsageError(
            menu_value="!",
            message="Unable to read Codex session logs",
            color=COLOR_RED,
            detail=first_read_error,
        )

    return UsageError(
        menu_value="--",
        message="No rate limit event found yet. Open or use Codex once to generate usage data.",
    )


def color_for_remaining(remaining_percent: Optional[int]) -> str:
    if remaining_percent is None:
        return COLOR_GRAY
    if remaining_percent >= 50:
        return COLOR_GREEN
    if remaining_percent >= 20:
        return COLOR_YELLOW
    return COLOR_RED


def format_percent(value: Optional[int]) -> str:
    if value is None:
        return "--"
    return f"{value}%"


def format_datetime(value: Optional[datetime]) -> str:
    if value is None:
        return "--"
    local_value = value.astimezone()
    now = datetime.now().astimezone()
    if local_value.date() == now.date():
        return local_value.strftime("%H:%M:%S")
    return f"{local_value.strftime('%b')} {local_value.day} {local_value.strftime('%H:%M')}"


def format_epoch(value: Optional[float]) -> str:
    if value is None:
        return "--"
    local_value = datetime.fromtimestamp(value, tz=timezone.utc).astimezone()
    return format_datetime(local_value)


def format_credits(credits: Any) -> Optional[str]:
    if not isinstance(credits, dict):
        return None
    if credits.get("unlimited") is True:
        return "unlimited"
    balance = credits.get("balance")
    if balance is not None:
        return str(balance)
    if credits.get("has_credits") is False:
        return "none"
    if credits.get("has_credits") is True:
        return "available"
    return None


def line_for_window(prefix: str, window: Optional[WindowUsage]) -> Sequence[str]:
    if window is None:
        return [f"{prefix} remaining: --", f"{prefix} resets: --"]
    return [
        f"{window.label} remaining: {format_percent(window.remaining_percent)}",
        f"{window.label} resets: {format_epoch(window.resets_at)}",
    ]


def render_error(error: UsageError) -> str:
    lines = [
        f"Codex {error.menu_value} | color={error.color}",
        "---",
        error.message,
    ]
    if error.detail:
        lines.append(f"Detail: {error.detail}")
    lines.append("Source: local Codex session logs")
    return "\n".join(lines)


def render_snapshot(snapshot: UsageSnapshot) -> str:
    primary_remaining = snapshot.primary.remaining_percent if snapshot.primary else None
    menu_value = format_percent(primary_remaining)
    color = color_for_remaining(primary_remaining)

    lines = [
        f"Codex {menu_value} | color={color}",
        "---",
        "Codex usage",
    ]
    lines.extend(line_for_window("Primary", snapshot.primary))
    lines.extend(line_for_window("Secondary", snapshot.secondary))

    plan = snapshot.plan_type if snapshot.plan_type else "--"
    lines.append(f"Plan: {plan}")

    credits = format_credits(snapshot.credits)
    if credits is not None:
        lines.append(f"Credits: {credits}")

    lines.append(f"Last reported: {format_datetime(snapshot.reported_at)}")
    lines.append("Source: local Codex session logs")
    return "\n".join(lines)


def render_for_swiftbar(sessions_dir: Path) -> str:
    result = find_latest_snapshot(sessions_dir)
    if isinstance(result, UsageError):
        return render_error(result)
    return render_snapshot(result)


def main() -> None:
    sessions_dir = Path(os.environ.get("CODEX_SESSIONS_DIR", str(DEFAULT_SESSIONS_DIR))).expanduser()
    print(render_for_swiftbar(sessions_dir))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Make the plugin executable**

```bash
chmod +x codex-usage.30s.py
```

- [ ] **Step 3: Run the focused verification**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output contains:

```text
Ran 5 tests

OK
```

- [ ] **Step 4: Run the plugin against local Codex logs**

Run:

```bash
python3 codex-usage.30s.py
```

Expected output starts with one of:

```text
Codex NN% | color=
```

or:

```text
Codex -- | color=#8E8E93
```

The output must contain:

```text
---
Source: local Codex session logs
```

- [ ] **Step 5: Commit the plugin**

```bash
git add codex-usage.30s.py tests/test_codex_usage_plugin.py
git commit -m "feat: add codex usage swiftbar plugin"
```

Expected output contains:

```text
[feat-swiftbar-codex-usage
```

## Task 4: Add Install Documentation

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

````markdown
# Codex Usage Menu Bar

A lightweight SwiftBar plugin for macOS that displays the latest locally reported Codex rate-limit remaining percentage.

## What It Shows

The menu bar displays the primary Codex rate-limit window remaining percentage:

```text
Codex 88%
```

The dropdown shows:

- Primary window remaining percentage and reset time
- Secondary window remaining percentage and reset time
- Plan type when present in local Codex logs
- Credits status when present in local Codex logs
- Last reported timestamp
- Source note

The value is based on the newest `token_count` event found in local Codex session logs. It is not an official public usage API.

## Security Boundary

The plugin:

- Reads `~/.codex/sessions/**/*.jsonl`
- Does not read `~/.codex/auth.json`
- Does not make network requests
- Does not write cache files
- Does not run shell commands

## Install SwiftBar

```bash
brew install swiftbar
```

## Install The Plugin

Create the SwiftBar plugin directory:

```bash
mkdir -p "$HOME/Library/Application Support/SwiftBar/Plugins"
```

Copy the plugin:

```bash
cp codex-usage.30s.py "$HOME/Library/Application Support/SwiftBar/Plugins/codex-usage.30s.py"
chmod +x "$HOME/Library/Application Support/SwiftBar/Plugins/codex-usage.30s.py"
```

Open SwiftBar and select:

```text
~/Library/Application Support/SwiftBar/Plugins
```

SwiftBar will run the plugin every 30 seconds.

## Local Verification

Run the plugin directly:

```bash
python3 codex-usage.30s.py
```

Expected output starts with `Codex NN%` when local Codex rate-limit data exists. If there is no local event yet, it starts with `Codex --` and explains the missing data in the dropdown lines.

Run focused verification:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output:

```text
Ran 5 tests

OK
```
````

- [ ] **Step 2: Verify README commands mention the correct plugin filename**

Run:

```bash
rg -n "codex-usage\\.30s\\.py|SwiftBar|auth\\.json|network|cache" README.md
```

Expected output includes lines for the plugin filename, SwiftBar install, `auth.json`, network requests, and cache files.

- [ ] **Step 3: Run verification again after docs are added**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output contains:

```text
Ran 5 tests

OK
```

- [ ] **Step 4: Commit documentation**

```bash
git add README.md
git commit -m "docs: add swiftbar install instructions"
```

Expected output contains:

```text
[feat-swiftbar-codex-usage
```

## Task 5: Final Local Verification

**Files:**
- No file changes expected.

- [ ] **Step 1: Confirm the branch and worktree state**

Run:

```bash
git status --short --branch
```

Expected output:

```text
## feat-swiftbar-codex-usage
```

- [ ] **Step 2: Run focused verification**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output contains:

```text
Ran 5 tests

OK
```

- [ ] **Step 3: Run the plugin against the real local Codex session directory**

Run:

```bash
python3 codex-usage.30s.py
```

Expected output starts with `Codex NN% | color=` when local rate-limit data exists. If the local Codex logs do not currently contain a usable `token_count.rate_limits` event, expected output starts with `Codex -- | color=#8E8E93` and includes a reason.

- [ ] **Step 4: Check that the plugin script does not read auth secrets or use networking**

Run:

```bash
rg -n "auth\\.json|urllib|requests|http|socket|subprocess|os\\.system|Popen|open\\(" codex-usage.30s.py
```

Expected output is empty or contains only harmless source-code text that is not an auth read, network call, or shell execution. If the command prints a real network, auth, or shell-execution usage, remove that code and repeat Tasks 3 and 5.

- [ ] **Step 5: Record final commit state**

Run:

```bash
git log --oneline --decorate -5
```

Expected output shows the recent commits for project hygiene, verification, plugin implementation, documentation, and the original design/plan commits.

## Plan Self-Review

Spec coverage:

- Single SwiftBar plugin script: Task 3 creates `codex-usage.30s.py`.
- Local Codex session parsing: Task 3 implements discovery and JSONL parsing.
- Compact menu bar percentage: Task 3 renders `Codex NN%`.
- Dropdown details: Task 3 renders primary/secondary windows, resets, plan, credits, last reported, and source.
- Conservative error states: Task 3 renders missing directory, missing event, malformed JSON skip behavior, missing fields, and read errors.
- Installation instructions: Task 4 documents SwiftBar install and plugin copy commands.
- Security boundaries: Task 3 avoids auth/network/write/shell behavior; Task 4 documents the boundary; Task 5 checks for risky code patterns.

Placeholder scan:

- The plan contains concrete file paths, code, commands, and expected outputs.
- The plan does not contain placeholder requirement markers.

Type consistency:

- The verification file calls `render_for_swiftbar(Path)`, which Task 3 defines.
- The plugin uses `UsageSnapshot`, `WindowUsage`, and `UsageError` consistently across parser and renderer functions.
