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
