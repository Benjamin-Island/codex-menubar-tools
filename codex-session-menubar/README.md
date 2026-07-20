# Codex Session Menu Bar

A native, read-only macOS menu bar monitor for live interactive Codex CLI TUI sessions running in terminals.

## What It Shows

The status item displays a terminal symbol and the number of live interactive TUI sessions. Its menu shows only:

- State: `运行中` or `停滞`
- Task description
- Working directory
- `Refresh` and `Quit`

It deliberately does not calculate or display process, session, task, or idle durations.

`运行中` means the associated rollout log has an unmatched `task_started` event and was updated less than five minutes ago. Every other live TUI is shown as `停滞`, including the normal case where Codex is waiting for input.

Task descriptions use the named session from `~/.codex/session_index.jsonl`, then the first user message, then the working-directory name. Visible task text is limited to 60 characters; the full value remains available as a tooltip.

## Strict Interactive-TUI Scope

The monitor includes only top-level, current-user, terminal-attached native Codex processes launched as `codex`, `codex resume`, or `codex fork`.

It excludes `codex exec`, `codex review`, `app-server`, background automation, ChatGPT/Codex App processes, IDE integrations, OpenClaw-managed processes, MCP servers, and subagent threads.

## Local Inputs and Privacy

The app reads:

- Current-user process metadata through macOS `libproc` and `sysctl`
- Writable open-file paths to correlate a live process with its rollout log
- Matched `~/.codex/sessions/**/*.jsonl` files
- `~/.codex/session_index.jsonl` for optional session names

The app does not read `~/.codex/auth.json`, make network requests, run shell commands, write caches or Codex state, or send/steer/interrupt/terminate sessions. It only displays local status.

## Build the App

From this directory:

```bash
macos/CodexSessionMenuBar/scripts/build-app.sh
```

The generated bundle is:

```text
macos/CodexSessionMenuBar/dist/CodexSessionMenuBar.app
```

Open it with:

```bash
open macos/CodexSessionMenuBar/dist/CodexSessionMenuBar.app
```

The app is an accessory menu bar app and has no Dock icon. It refreshes immediately, on session-log changes, and every five seconds.

## Test and Build

```bash
swift test --package-path macos/CodexSessionMenuBar
swift build --package-path macos/CodexSessionMenuBar
swift build -c release --package-path macos/CodexSessionMenuBar
```

For isolated fixtures, the executable accepts `CODEX_SESSIONS_DIR` and `CODEX_SESSION_INDEX` environment overrides. Normal launches use the standard paths under `~/.codex`.
