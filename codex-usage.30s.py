#!/usr/bin/env python3
"""SwiftBar plugin for locally reported Codex rate-limit usage."""

from __future__ import annotations

import base64
import json
import os
import struct
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union


DEFAULT_SESSIONS_DIR = Path.home() / ".codex" / "sessions"
USAGE_BAR_WIDTH = 64
USAGE_BAR_HEIGHT = 18

_USAGE_BAR_IMAGE_CACHE: Dict[Tuple[str, Optional[int]], str] = {}
GLASS_DIGITS: Dict[str, Sequence[str]] = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "-": ("000", "000", "111", "000", "000"),
    "!": ("1", "1", "1", "0", "1"),
}


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
            detail=first_read_error,
        )

    return UsageError(
        menu_value="--",
        message="No rate limit event found yet. Open or use Codex once to generate usage data.",
    )


def format_percent(value: Optional[int]) -> str:
    if value is None:
        return "--"
    return f"{value}%"


def clamp_percent(value: Optional[int]) -> Optional[int]:
    if value is None:
        return None
    return min(100, max(0, int(value)))


def format_menu_value(value: Optional[int]) -> str:
    if value is None:
        return "--"
    return str(clamp_percent(value))


def blend_pixel(
    pixels: bytearray,
    width: int,
    height: int,
    x: int,
    y: int,
    color: Tuple[int, int, int, int],
) -> None:
    if x < 0 or y < 0 or x >= width or y >= height:
        return
    index = ((y * width) + x) * 4
    if index < 0 or index + 3 >= len(pixels):
        return

    src_r, src_g, src_b, src_a = color
    src_alpha = min(255, max(0, src_a)) / 255.0
    if src_alpha <= 0:
        return

    dst_alpha = pixels[index + 3] / 255.0
    out_alpha = src_alpha + dst_alpha * (1.0 - src_alpha)
    if out_alpha <= 0:
        return

    for offset, src_channel in enumerate((src_r, src_g, src_b)):
        dst_channel = pixels[index + offset]
        blended = (
            src_channel * src_alpha
            + dst_channel * dst_alpha * (1.0 - src_alpha)
        ) / out_alpha
        pixels[index + offset] = int(round(blended))
    pixels[index + 3] = int(round(out_alpha * 255))


def fill_rect(
    pixels: bytearray,
    width: int,
    height: int,
    x: int,
    y: int,
    rect_width: int,
    rect_height: int,
    color: Tuple[int, int, int, int],
) -> None:
    for row in range(y, y + rect_height):
        for col in range(x, x + rect_width):
            blend_pixel(pixels, width, height, col, row, color)


def point_in_rounded_rect(
    point_x: float,
    point_y: float,
    x: int,
    y: int,
    width: int,
    height: int,
    radius: int,
) -> bool:
    right = x + width
    bottom = y + height
    if point_x < x or point_y < y or point_x >= right or point_y >= bottom:
        return False

    corner_x = min(max(point_x, x + radius), right - radius)
    corner_y = min(max(point_y, y + radius), bottom - radius)
    return (point_x - corner_x) ** 2 + (point_y - corner_y) ** 2 <= radius ** 2


def rounded_rect_coverage(
    pixel_x: int,
    pixel_y: int,
    x: int,
    y: int,
    width: int,
    height: int,
    radius: int,
) -> float:
    hits = 0
    samples = ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75))
    for offset_x, offset_y in samples:
        if point_in_rounded_rect(
            pixel_x + offset_x,
            pixel_y + offset_y,
            x,
            y,
            width,
            height,
            radius,
        ):
            hits += 1
    return hits / len(samples)


def fill_rounded_rect(
    pixels: bytearray,
    canvas_width: int,
    canvas_height: int,
    x: int,
    y: int,
    rect_width: int,
    rect_height: int,
    radius: int,
    color: Tuple[int, int, int, int],
) -> None:
    for row in range(y, y + rect_height):
        for col in range(x, x + rect_width):
            coverage = rounded_rect_coverage(col, row, x, y, rect_width, rect_height, radius)
            if coverage <= 0:
                continue
            r, g, b, alpha = color
            blend_pixel(
                pixels,
                canvas_width,
                canvas_height,
                col,
                row,
                (r, g, b, int(round(alpha * coverage))),
            )


def stroke_rounded_rect(
    pixels: bytearray,
    canvas_width: int,
    canvas_height: int,
    x: int,
    y: int,
    rect_width: int,
    rect_height: int,
    radius: int,
    stroke_width: int,
    color: Tuple[int, int, int, int],
) -> None:
    for row in range(y, y + rect_height):
        for col in range(x, x + rect_width):
            outer = rounded_rect_coverage(col, row, x, y, rect_width, rect_height, radius)
            inner = rounded_rect_coverage(
                col,
                row,
                x + stroke_width,
                y + stroke_width,
                rect_width - stroke_width * 2,
                rect_height - stroke_width * 2,
                max(0, radius - stroke_width),
            )
            coverage = max(0.0, outer - inner)
            if coverage <= 0:
                continue
            r, g, b, alpha = color
            blend_pixel(
                pixels,
                canvas_width,
                canvas_height,
                col,
                row,
                (r, g, b, int(round(alpha * coverage))),
            )


def png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = zlib.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def encode_png_rgba(width: int, height: int, pixels: bytes) -> bytes:
    raw_rows = bytearray()
    stride = width * 4
    for row in range(height):
        raw_rows.append(0)
        start = row * stride
        raw_rows.extend(pixels[start : start + stride])

    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            png_chunk(b"IDAT", zlib.compress(bytes(raw_rows), 9)),
            png_chunk(b"IEND", b""),
        ]
    )


def glass_fill_color(percent: Optional[int]) -> Tuple[int, int, int, int]:
    if percent is None:
        return (160, 170, 185, 118)
    if percent <= 20:
        return (255, 103, 103, 174)
    if percent <= 50:
        return (255, 194, 91, 166)
    return (91, 176, 255, 174)


def add_glass_texture(pixels: bytearray, width: int, height: int) -> None:
    for y in range(3, height - 3):
        for x in range(3, width - 3):
            value = (x * 17 + y * 31) % 29
            if value == 0:
                blend_pixel(pixels, width, height, x, y, (255, 255, 255, 18))
            elif value == 7:
                blend_pixel(pixels, width, height, x, y, (70, 90, 120, 8))


def text_width(text: str, scale: int, spacing: int) -> int:
    total = 0
    for char in text:
        glyph = GLASS_DIGITS.get(char)
        if glyph is None:
            continue
        total += len(glyph[0]) * scale + spacing
    return max(0, total - spacing)


def draw_text(
    pixels: bytearray,
    width: int,
    height: int,
    text: str,
    x: int,
    y: int,
    scale: int,
    color: Tuple[int, int, int, int],
) -> None:
    cursor_x = x
    spacing = 1
    for char in text:
        glyph = GLASS_DIGITS.get(char)
        if glyph is None:
            continue
        for glyph_y, row in enumerate(glyph):
            for glyph_x, value in enumerate(row):
                if value != "1":
                    continue
                fill_rect(
                    pixels,
                    width,
                    height,
                    cursor_x + glyph_x * scale,
                    y + glyph_y * scale,
                    scale,
                    scale,
                    color,
                )
        cursor_x += len(glyph[0]) * scale + spacing


def glass_usage_bar_image(label: str, remaining_percent: Optional[int]) -> str:
    percent = clamp_percent(remaining_percent)
    cache_key = (label, percent)
    if cache_key in _USAGE_BAR_IMAGE_CACHE:
        return _USAGE_BAR_IMAGE_CACHE[cache_key]

    width = USAGE_BAR_WIDTH
    height = USAGE_BAR_HEIGHT
    pixels = bytearray(width * height * 4)

    fill_rounded_rect(pixels, width, height, 1, 2, width - 2, height - 4, 8, (20, 26, 34, 42))
    fill_rounded_rect(pixels, width, height, 0, 1, width, height - 3, 8, (244, 248, 252, 126))
    add_glass_texture(pixels, width, height)
    fill_rounded_rect(pixels, width, height, 3, 4, width - 6, height - 8, 5, (255, 255, 255, 58))

    track_x = 4
    track_y = 5
    track_width = width - 8
    track_height = height - 10
    if percent is not None:
        progress_width = int(round(track_width * (percent / 100.0)))
        if percent > 0:
            progress_width = max(2, progress_width)
        progress_width = min(track_width, progress_width)
        fill_rounded_rect(
            pixels,
            width,
            height,
            track_x,
            track_y,
            progress_width,
            track_height,
            min(4, max(1, progress_width // 2)),
            glass_fill_color(percent),
        )

    fill_rounded_rect(pixels, width, height, 1, 2, width - 2, 7, 7, (255, 255, 255, 62))
    stroke_rounded_rect(pixels, width, height, 0, 1, width, height - 3, 8, 1, (255, 255, 255, 118))
    stroke_rounded_rect(pixels, width, height, 1, 2, width - 2, height - 5, 7, 1, (42, 58, 78, 34))

    scale = 2
    spacing = 1
    draw_width = text_width(label, scale, spacing)
    text_x = max(0, (width - draw_width) // 2)
    text_y = 4
    draw_text(pixels, width, height, label, text_x, text_y + 1, scale, (255, 255, 255, 92))
    draw_text(pixels, width, height, label, text_x, text_y, scale, (21, 28, 38, 238))

    png_data = encode_png_rgba(width, height, bytes(pixels))
    encoded = base64.b64encode(png_data).decode("ascii")
    _USAGE_BAR_IMAGE_CACHE[cache_key] = encoded
    return encoded


def render_menu_line(label: str, remaining_percent: Optional[int]) -> str:
    return f" | image={glass_usage_bar_image(label, remaining_percent)}"


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
        render_menu_line(error.menu_value, None),
        "---",
        error.message,
    ]
    if error.detail:
        lines.append(f"Detail: {error.detail}")
    lines.append("Source: local Codex session logs")
    return "\n".join(lines)


def render_snapshot(snapshot: UsageSnapshot) -> str:
    primary_remaining = snapshot.primary.remaining_percent if snapshot.primary else None
    menu_value = format_menu_value(primary_remaining)

    lines = [
        render_menu_line(menu_value, primary_remaining),
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
