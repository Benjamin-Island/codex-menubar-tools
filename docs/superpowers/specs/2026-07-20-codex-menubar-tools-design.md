# Codex Menu Bar Tools Design

## Summary

Create a private `benjaminazz1210/codex-menubar-tools` GitHub repository that contains two independent native macOS menu bar applications:

- `codex-usage-menubar`: the existing Codex rate-limit indicator, preserved without behavior changes.
- `codex-session-menubar`: a new read-only indicator for interactive Codex CLI TUI sessions running in terminal applications.

The new session monitor displays only each live TUI session's state, task description, and working directory. It does not control sessions, calculate durations, inspect noninteractive Codex processes, or access the network.

## Goals

- Preserve the existing usage menu bar application as a separately buildable `.app`.
- Detect all live, top-level, interactive Codex TUI sessions owned by the current macOS user.
- Exclude Codex App, IDE, OpenClaw, noninteractive commands, servers, automations, and subagents.
- Display a total TUI count in the menu bar.
- Display each session's running/stalled state, task description, and working directory in the menu.
- Preserve existing Git history while migrating to one tools repository.
- Verify the new local and GitHub repository before deleting the old GitHub repository.

## Non-goals

- Monitoring cloud tasks, SSH sessions, Codex App, IDE integrations, OpenClaw, or remote app servers.
- Monitoring `codex exec`, `codex app-server`, MCP servers, background automations, or subagent threads.
- Switching to, steering, interrupting, or terminating a TUI session.
- Showing session duration, task duration, idle duration, token usage, or rate limits in the new session application.
- Sending telemetry or making network requests from either menu bar application.
- Introducing Electron, Tauri, third-party packages, or a shared runtime between the two applications.

## Repository Architecture

The migrated repository will have this structure:

```text
~/Downloads/codex-menubar-tools/
├── README.md
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── codex-usage-menubar/
│   ├── README.md
│   └── macos/
│       └── CodexUsageMenuBar/
└── codex-session-menubar/
    ├── README.md
    └── macos/
        └── CodexSessionMenuBar/
            ├── Package.swift
            ├── Sources/
            │   ├── CodexSessionCore/
            │   └── CodexSessionMenuBar/
            ├── Tests/
            │   └── CodexSessionCoreTests/
            └── scripts/
                └── build-app.sh
```

The repository root is the only Git root. The two applications remain independent Swift packages and produce independent `.app` bundles.

## Technology and Platform Constraints

- Apple Swift 6 and Swift Package Manager.
- Native AppKit menu bar applications using `NSApplication`, `NSStatusItem`, and `NSMenu`.
- Minimum deployment target: macOS 14.
- XCTest for unit and integration-style core tests.
- CoreServices FSEvents for immediate session-log refreshes.
- Native macOS process and file-descriptor APIs for discovery and correlation.
- No third-party dependencies.
- No network access from the applications.
- No shell commands launched by the applications.

## Component Boundaries

### `CodexSessionCore`

`CodexSessionCore` owns testable data acquisition and interpretation. It contains:

- A process inventory abstraction and macOS implementation.
- Interactive TUI candidate classification and wrapper/child de-duplication.
- Open-file discovery for locating a process's active Codex rollout JSONL.
- A fallback process-to-session matcher based on process start time, working directory, and session metadata.
- Parsers for session metadata, session names, user messages, and task lifecycle events.
- Session state derivation and stable sorting.
- Public immutable snapshot and error models consumed by the AppKit target.

The core target has no AppKit dependency and exposes protocols for process and file-descriptor providers so tests can use deterministic fixtures.

### `CodexSessionMenuBar`

`CodexSessionMenuBar` owns application lifecycle and presentation. It contains:

- The accessory `NSApplication` entry point.
- `NSStatusItem` configuration and menu rendering.
- FSEvents monitoring of `~/.codex/sessions`.
- A five-second fallback timer.
- Manual Refresh and Quit actions.
- Background refresh orchestration with main-thread UI updates.

It does not parse JSONL or contain process-classification rules.

## Monitored Process Scope

A displayed entry must represent a live, top-level, terminal-attached, interactive Codex TUI owned by the current user.

Included launch forms are:

- `codex`
- `codex resume`
- `codex fork`

The implementation will identify the native Codex child process as the canonical process and will not count its Node launcher separately.

The implementation will exclude:

- Any process without an interactive controlling terminal.
- `codex exec` and other noninteractive modes.
- `codex app-server` and remote-control server processes.
- Codex processes launched by ChatGPT/Codex App or IDE integrations.
- OpenClaw-managed Codex processes.
- MCP servers and background automations.
- Logs whose metadata is not `source: cli`, `originator: codex-tui`, and `thread_source: user`.
- Subagent threads.

## Process-to-Session Correlation

The primary correlation mechanism inspects each canonical native Codex process's open file descriptors and selects a writable file under `~/.codex/sessions` with a `.jsonl` extension. Interactive Codex TUI processes keep their active rollout JSONL open for writing, so this mechanism supports resumed sessions and multiple sessions using the same working directory.

If open-file inspection temporarily fails, the application uses process start time, process working directory, and `session_meta` fields as a fallback. It considers only unassigned top-level TUI logs whose working directory matches exactly and whose metadata timestamp is between the process start time and 120 seconds after it, then selects the closest timestamp. A successful PID-to-log association is cached in memory until the process exits. The application never writes an association cache to disk.

If a process is confirmed as an interactive TUI but no log can be associated, it remains visible. Its task description falls back to the working-directory name and its state is conservatively reported as stalled.

## Task Description

Task descriptions use this priority order:

1. The `thread_name` from `~/.codex/session_index.jsonl` when the session has been named.
2. The first `event_msg` whose payload type is `user_message`.
3. The final component of the working-directory path.

Whitespace is collapsed for menu display. The visible task description is limited to 60 characters, with the full value exposed as a tooltip. No later user or assistant messages are retained or displayed.

## Session State

The public state model has exactly two values:

- `running`: the newest relevant lifecycle sequence contains a `task_started` event without a matching later `task_complete`, and the rollout log has updated within the last five minutes.
- `stalled`: the newest task completed, no task has started, the process could not be associated with a valid log, or an incomplete task has produced no rollout-log update for five minutes.

Stalled includes the normal case where an interactive TUI is waiting for user input. It is not presented as an error.

The application does not calculate or display process, session, task, or idle durations.

## Refresh Data Flow

1. Application launch performs an immediate refresh.
2. The process provider enumerates current-user processes and returns canonical interactive TUI candidates.
3. The correlator resolves one rollout JSONL per candidate by open-file inspection or fallback metadata matching.
4. The parser reads only associated logs and the session-name index.
5. The state reducer produces one immutable display snapshot per live TUI.
6. Snapshots are sorted with running sessions first, then by normalized task description.
7. The AppKit controller updates the status-item count and rebuilds the menu on the main thread.
8. FSEvents schedules a debounced refresh when session logs change.
9. A five-second timer detects process creation, process exit, and missed filesystem events.
10. Refresh coalescing prevents concurrent scans; a refresh request received during a scan schedules one follow-up scan.

A process that exits disappears no later than the next five-second refresh.

## Menu Design

The menu bar item uses a system terminal symbol and the number of live interactive TUI sessions, for example `terminal 3`.

The dropdown contains:

```text
Codex CLI Sessions
3 interactive TUI sessions

● 运行中 — 修复登录流程测试
  /Users/benjaminz/Downloads/customer-api

● 停滞 — 重构知识库检索模块
  /Users/benjaminz/Downloads/knowledge-base

● 停滞 — 更新部署文档
  /Users/benjaminz/Downloads/docs-site

────────────────────
Refresh
Quit
```

Presentation rules:

- Running uses a green status symbol.
- Stalled uses a yellow status symbol because it commonly means normal user-input wait time rather than an error.
- The complete task description and working directory are available as tooltips when visible text is truncated.
- Session rows and paths are informational and have no click actions.
- Running sessions sort before stalled sessions; each group sorts by task description.
- With no live TUI, the status item displays `0` and the menu states `No interactive Codex TUI sessions`.
- Refresh retries immediately; Quit terminates only the menu bar application.

## Error Handling

- Ignore an incomplete final JSONL line and retry it on the next refresh.
- Skip malformed records while continuing to use the newest valid record in the same file.
- Treat a missing sessions directory as an empty list and retry every five seconds.
- Continue timer refreshes if FSEvents cannot start.
- Preserve a live interactive TUI entry when correlation fails, using the documented task and state fallbacks.
- If process enumeration or directory access is denied, display `!` in the status item and a concise retryable error in the menu.
- Keep the most recent successful snapshot while a refresh is in progress, but do not retain stale entries after a successful process scan proves their PIDs exited.
- Do not crash because a process exits between enumeration, file-descriptor inspection, and metadata reads.

## Privacy and Security Boundary

The session application:

- Reads process metadata only for discovery of current-user interactive Codex TUI processes.
- Reads open-file paths only to identify the active rollout JSONL.
- Reads matched files under `~/.codex/sessions` and the session-name index.
- Reads only the first user message needed for a task description; it does not display later conversation content.
- Does not read `~/.codex/auth.json` or other credential stores.
- Does not make network requests.
- Does not launch shell commands.
- Does not write caches, logs, or Codex state.
- Does not send, steer, interrupt, or terminate TUI sessions.

## Test Strategy

### Core unit tests

- Accept plain `codex`, `codex resume`, and `codex fork` interactive TUI snapshots.
- Reject `exec`, `app-server`, IDE, Codex App, OpenClaw, MCP server, automation, non-terminal, and other-user snapshots.
- De-duplicate Node wrapper and native child processes.
- Resolve distinct rollout logs for simultaneous TUI processes with the same working directory.
- Resolve resumed sessions through an open rollout file.
- Use metadata fallback when open-file inspection fails.
- Read a named session from `session_index.jsonl`.
- Fall back from session name to first user message and then directory name.
- Collapse whitespace and truncate displayed task descriptions to 60 characters without corrupting Unicode.
- Derive running from an unmatched recent `task_started`.
- Derive stalled from `task_complete`, absent tasks, missing association, and the five-minute stale threshold.
- Tolerate malformed JSON, an incomplete final line, deleted processes, missing directories, and permission errors.
- Sort running sessions first and preserve deterministic task ordering.

### Controller and rendering tests

- Render the total live TUI count.
- Render empty and retryable error states.
- Render task, state, and working-directory items without actions.
- Coalesce overlapping refreshes and perform a queued follow-up refresh.
- Remove a session after a successful scan no longer reports its PID.

### Full verification

- Run both Swift packages' complete XCTest suites.
- Build both packages in debug and release configurations.
- Run both application-bundle build scripts.
- Verify both bundles with `codesign --verify`.
- Re-run the existing usage application's tests to prove the repository migration did not change behavior.

## Git and GitHub Migration

The migration preserves the current repository history and uses the required feature-branch and pull-request workflow.

1. Create a feature branch from the existing `main` before any tracked edits.
2. Commit the approved design and implementation plan on the feature branch.
3. Create the private `benjaminazz1210/codex-menubar-tools` repository with `main` as its default branch.
4. Push the existing, unmodified `main` history to the new repository as its baseline.
5. Restructure the working tree so existing usage-app files live under `codex-usage-menubar`, then add the new session application under `codex-session-menubar`.
6. Push the feature branch to the new repository and open a pull request to `main`.
7. Run all local verification and confirm the pull request checks and contents.
8. Merge through the pull request.
9. Verify the new repository's default branch, final commit SHA, directory structure, visibility, and accessibility.
10. Delete `benjaminazz1210/codex-usage-menubar` only after every preceding verification succeeds.
11. Verify the new repository again and ensure the local `origin` points to `benjaminazz1210/codex-menubar-tools`.

If any verification fails, the old GitHub repository remains untouched and the migration stops at the failed gate.

## Acceptance Criteria

- `codex-menubar-tools` is a private GitHub repository whose default branch is `main`.
- The repository contains two independently buildable native macOS menu bar applications.
- The existing usage application retains its current behavior and passes its existing tests.
- The session application lists every detectable live top-level interactive Codex TUI and excludes all documented non-TUI sources.
- The status item displays the total live TUI count.
- Each session displays only state, task description, and working directory.
- Session state is exactly running or stalled, using the approved lifecycle and five-minute rules.
- The new application performs no network requests, launches no shell commands, and does not read credentials.
- Full tests, debug/release builds, app-bundle builds, and code-sign verification pass for both applications.
- The old GitHub repository is deleted only after the new repository is verified.
