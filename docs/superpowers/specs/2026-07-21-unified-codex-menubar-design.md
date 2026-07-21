# Unified Codex Menu Bar Design

**Date:** 2026-07-21

**Status:** Approved in conversation; awaiting review of this written specification

## Summary

Replace `CodexUsageMenuBar.app` and `CodexSessionMenuBar.app` with one native macOS application named **Codex Menu Bar**. The unified application combines rate-limit visibility, 30 weeks of read-only Token history, per-day and per-session usage details, and live interactive Codex TUI monitoring in one SwiftUI panel opened from one menu bar item.

The implementation creates a new Swift Package first, migrates existing behavior under tests, and removes the two old packages only after the unified application passes the complete verification matrix. It remains local-only, read-only with respect to Codex data, network-free, and free of third-party runtime dependencies.

## Goals

- Display the primary Codex rate-limit remaining percentage and live interactive TUI count in one menu bar item.
- Replace text-only `NSMenu` dropdowns with a native SwiftUI panel hosted in an `NSPopover`.
- Show 30 calendar weeks of daily Token activity in a heatmap.
- Show exact daily Total, Input, Cached input, Output, and Reasoning Token values.
- Attribute each day's Token increments to individual Codex sessions and expose per-session details.
- Preserve the current strict definition of a live interactive terminal Codex session.
- Preserve existing rate-limit selection, process discovery, session association, naming, refresh, and error-tolerance behavior.
- Rebuild history from local logs on every launch without writing a database or cache.
- Leave the repository with one maintained application, one build path, and one set of README instructions.

## Non-Goals

- GitHub Releases, Developer ID signing, Apple notarization, `.pkg` installers, or automatic updates.
- Pricing or cost estimates derived from Token counts.
- Cloud synchronization, telemetry, analytics, or network requests.
- Persisting history after source Codex logs are deleted.
- Displaying conversation bodies beyond the first user message used as a fallback session name.
- Sending input to, resuming, steering, interrupting, or terminating Codex sessions.
- Supporting macOS versions earlier than macOS 14.
- Maintaining the two legacy `.app` bundles after migration succeeds.
- Bundling a README video without user-provided media.

## Product Identity and Platform

- Product name: `Codex Menu Bar`
- Swift package and executable name: `CodexMenuBar`
- Application bundle: `CodexMenuBar.app`
- Bundle identifier: `dev.benjamin.codex-menubar`
- Minimum operating system: macOS 14
- Swift tools version: 6.0
- UI language: English only for the first unified version
- UI frameworks: AppKit for the application lifecycle, status item, and popover; SwiftUI for panel content

## Repository and Target Structure

The new package lives at:

```text
codex-menubar/macos/CodexMenuBar/
├── Package.swift
├── Sources/
│   ├── CodexMenuBarCore/
│   └── CodexMenuBar/
├── Tests/
│   ├── CodexMenuBarCoreTests/
│   └── CodexMenuBarTests/
└── scripts/build-app.sh
```

`CodexMenuBarCore` owns Foundation- and Darwin-based domain logic and exposes immutable `Sendable` snapshots. `CodexMenuBar` owns AppKit integration, refresh coordination, clipboard actions, and SwiftUI views. Core types must not import SwiftUI or AppKit.

The existing `codex-usage-menubar` and `codex-session-menubar` directories remain intact while their behavior is migrated. They are deleted only after the new package passes all migrated tests and end-to-end verification.

## Core Components

### Log Discovery and In-Memory Index

`CodexLogIndex` discovers JSONL files under the configured Codex sessions directory and reads `session_index.jsonl` for optional thread names. Each indexed file records its path, modification date, byte size, session metadata, first user message, lifecycle summary, Token events, newest rate-limit event, and parse warnings.

The index is held only in memory. On refresh, unchanged files are reused when path, modification date, and byte size all match. Changed or new files are reparsed, and deleted files are removed from the index. Application restart always reconstructs the index from source logs.

Discovery includes files capable of contributing events to the visible 30-week interval and every rollout file associated with a currently live interactive process. The implementation may use modification dates to avoid parsing obviously irrelevant old files, but daily attribution always uses event timestamps rather than file dates.

### Token History Aggregator

Each valid `token_count` event can contain cumulative `total_token_usage` fields:

- `total_tokens`
- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_output_tokens`

For each rollout file, events are processed in timestamp and file sequence order. The aggregator subtracts the preceding cumulative value from the current value for each field. The first valid cumulative value in a sequence is measured from zero. Equal cumulative values produce zero increment. If any cumulative field decreases, that field begins a new sequence and the new cumulative value becomes its increment.

Each nonnegative increment is assigned to the system-local calendar day containing the event timestamp. Events without a valid timestamp do not contribute to daily history because assigning them using file modification time would create false dates. They may still contribute to current rate-limit selection when existing fallback rules allow it.

Daily and per-session totals contain these values:

- Total: increment of `total_tokens`
- Input: increment of `input_tokens`
- Cached input: increment of `cached_input_tokens`
- Output: increment of `output_tokens`
- Reasoning: increment of `reasoning_output_tokens`

Cached input is a subset of Input, and Reasoning is a detail field associated with generation. Neither is added again to Total. The UI never labels Token totals as financial cost.

Token history includes every local Codex rollout containing usable Token events, including interactive TUI, `codex exec`, review, IDE/App, and other sources. Source kind is derived from available session metadata such as `source`, `thread_source`, and `originator`, with an `Other` fallback. Source classification affects labels only; it does not exclude usage.

### Rate-Limit Reader

The unified application preserves the current usage application's selection rules. It prefers the newest valid standard event whose `limit_id` is `codex`. When no standard limit exists, it falls back to the newest available named limit. It exposes primary and secondary remaining percentages, reset times, plan type, credits description, report time, and source path.

### Live Session Inventory

The live session subsystem preserves the existing session application's strict scope. It includes only top-level, current-user, controlling-terminal-attached native Codex processes launched as plain `codex`, `codex resume`, or `codex fork` interactive TUIs.

It excludes noninteractive subcommands, Codex App and IDE processes, OpenClaw, MCP servers, automation, Node wrapper duplicates, other-user processes, and child agent threads. Open rollout paths are preferred for process-to-log correlation. The existing working-directory and process-start fallback remains available, and a valid PID association is cached only in memory until that process exits.

Live state remains exactly:

- `running`: the newest lifecycle sequence has an unmatched `task_started` event and the associated rollout was updated less than five minutes ago.
- `stalled`: every other detected live interactive TUI, including normal input-wait states.

Running sessions sort before stalled sessions, followed by case-insensitive display name and PID for deterministic ordering.

### Session Naming

Both historical and live session displays use this priority order:

1. `thread_name` from `session_index.jsonl`
2. First `user_message` event in the rollout
3. Final component of the session working directory
4. `Untitled session`

Whitespace is collapsed. List rows display at most 60 characters without breaking Unicode; the detail panel exposes the complete resolved name. No later user or assistant messages are retained in the display model.

## History Window and Heatmap

The visible history interval contains the current local calendar week and the preceding 29 complete weeks. Weeks begin on Monday, producing exactly 30 columns and seven rows. Future days in the current week are present as disabled empty cells and are not included in statistics.

The heatmap uses gray for zero or missing usage and four progressively stronger accent levels for nonzero usage. Levels are derived from quartiles of nonzero daily Total values in the visible interval. When too few distinct values exist, adjacent levels may collapse. Hover and accessibility text always expose the exact date and Total value, so color is never the only carrier of information.

The default selected date is today. Selecting a day updates the right-hand detail panel. Daily session rows sort by that day's Total descending, followed by session name. A session spanning multiple days appears in each relevant day with only the increments attributed to that day.

## Application and Refresh Data Flow

1. `NSApplication` launches as an accessory application with no Dock icon.
2. `StatusController` creates one variable-width `NSStatusItem` and one transient `NSPopover`.
3. `DashboardStore` publishes an initial loading state.
4. A background refresh discovers processes and logs, updates the in-memory index, reduces rate-limit/history/session snapshots, and emits one immutable dashboard snapshot.
5. The main actor applies the snapshot to the menu bar renderer and SwiftUI views.
6. Session-directory monitoring requests a debounced refresh when relevant JSONL files change.
7. A five-second timer detects process changes, missing filesystem events, and retryable failures.
8. Refresh requests arriving during an active refresh set a follow-up flag rather than starting concurrent scans.
9. The most recent successful data remains visible while refresh is in progress.
10. Application termination discards all indexed and aggregated state.

## Menu Bar Presentation

The single menu bar item combines the primary remaining percentage and live interactive session count, conceptually:

```text
[72]  terminal 3
```

The remaining percentage retains the current compact filled indicator treatment. A terminal symbol and integer count follow it. A rate-limit error replaces the percentage label with `!` while preserving the live session count. Zero sessions remains visible as `0`. Accessibility labels announce both values.

Clicking the item opens a roughly 620 by 520 point transient popover. Clicking outside closes it. The popover must remain within the visible screen and tolerate menu bar placement near either display edge.

## SwiftUI Information Architecture

The popover header uses three English tabs:

```text
Overview | History | Sessions 3
```

The numeric badge on Sessions mirrors the detected interactive TUI count. The panel uses system typography, materials, colors, spacing, dark mode, keyboard focus, and accessibility labels. No third-party UI or chart dependency is added.

### Overview

- Three leading cards: 5-hour remaining, 7-day remaining, and Today Tokens.
- Main region: compact 30-week activity heatmap.
- Right detail region: current interactive session summary.
- Selecting a heatmap day switches to History with that day selected.
- Selecting a live session switches to Sessions with that session selected.

### History

- Main region: complete 7-row by 30-column heatmap.
- Right detail region defaults to selected-day totals for Total, Input, Cached input, Output, and Reasoning.
- The right region also lists all sessions contributing to the selected date, ordered by daily Total.
- Each session row shows resolved name, project directory when known, source kind, and daily Total.
- Selecting a session replaces the right region with that session's selected-day Token breakdown and metadata.
- A Back to Day control restores the daily summary without changing the selected date.

### Sessions

- Main region: only currently live interactive terminal sessions.
- Each card shows Running or Stalled, resolved name, working directory, and the rollout's current cumulative Total.
- Right detail region shows complete name, state explanation, working directory, absolute last-log-update timestamp, and cumulative Total/Input/Cached input/Output/Reasoning.
- Copy Path writes only the working-directory string to the system pasteboard.
- No session control or conversation interaction is provided.

### Footer

The footer shows absolute last-updated time plus Refresh and Quit. Refresh schedules an immediate coalesced refresh. Quit terminates only Codex Menu Bar.

## Loading, Empty, Partial, and Error States

Rate limits, history, and live sessions maintain independent presentation states. Failure in one subsystem must not erase successful data from another.

- Initial launch uses lightweight loading placeholders.
- A missing sessions directory produces empty usage/history/session states and remains retryable.
- No Token events produces a clear History empty state rather than an error.
- No live interactive processes produces a Sessions empty state and menu bar count `0`.
- Malformed records, unknown fields, and an incomplete final JSONL line are skipped while valid records in the same file remain usable.
- A single unreadable file produces a partial-data warning while other files remain included.
- Top-level process enumeration denial produces a Sessions error only.
- Session-directory enumeration denial produces a retryable History/Usage error; the most recent successful snapshot remains visible during transient refresh failure.
- A process disappearing during inspection is skipped without crashing.
- Deleted logs are removed from the in-memory index on the next successful refresh, and their historical contribution disappears.
- Failure to start filesystem monitoring leaves the five-second timer active.

## Privacy and Security Boundary

The application may read:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/session_index.jsonl`
- Current-user process metadata required to discover interactive native Codex TUIs
- Writable open-file paths required to associate a live process with its rollout

The application must not:

- Read `~/.codex/auth.json`, macOS Keychain credentials, or unrelated files
- Make network requests
- Execute shell commands
- Write caches, databases, logs, analytics, or Codex state
- Persist first-message text, history aggregates, or process associations
- Send, resume, steer, interrupt, or terminate Codex sessions

The only user-authorized write outside the application process is placing a selected working-directory path on the system pasteboard.

## TDD and Test Strategy

Every new behavior follows a red-green-refactor cycle. A focused test is written and observed failing for the expected missing behavior before production code is added. The focused test and then the complete applicable suite must pass before refactoring or proceeding.

### Token and Index Tests

- First cumulative event measured from zero.
- Consecutive cumulative values converted to increments.
- Duplicate cumulative values contribute zero.
- Decreasing fields restart independently without negative usage.
- Input, Cached input, Output, Reasoning, and Total remain separate without double addition.
- Events distribute across local day, week, month, daylight-saving, and year boundaries.
- The visible interval contains exactly 30 Monday-based calendar weeks.
- Future cells in the current week remain disabled and empty.
- Missing timestamps are excluded from daily history.
- Multiple sessions aggregate into daily totals and deterministic session ordering.
- Interactive and noninteractive source kinds both contribute to history.
- Incremental refresh reuses unchanged indexed files, reparses changed files, adds new files, and removes deleted files.
- Malformed, partially written, unreadable, and unknown-schema records produce the documented partial results.

### Rate-Limit and Session Migration Tests

All current usage and session behavior tests are migrated before legacy packages are removed. This includes canonical `codex` limit preference, named-limit fallback, process classification, wrapper de-duplication, open-file correlation, metadata fallback boundaries, cached associations, missing paths, lifecycle state, Unicode-safe naming, named-session priority, and live inventory smoke coverage.

### Store and Presentation Tests

- Loading, content, empty, partial, and error states for each independent subsystem.
- Combined menu bar labels for valid, missing, and error rate-limit values with zero or multiple sessions.
- Overview selection routes to the correct History date or live Session.
- History date selection and session drill-down/back behavior.
- Running-before-stalled session ordering.
- Refresh coalescing schedules exactly one follow-up refresh.
- Copy Path sends exactly the selected working directory to an injected pasteboard abstraction.
- UI-facing formatters produce stable English labels and accessibility text.

## Migration and Git Workflow

1. Create and remain on `feature/unified-codex-menubar` for all tracked work.
2. Commit this approved design specification.
3. Write and commit an implementation plan before production implementation.
4. Create the new package alongside both legacy packages.
5. Implement the in-memory log index and Token aggregation with TDD.
6. Migrate rate-limit behavior and its tests.
7. Migrate live-session behavior and its tests.
8. Implement the unified store, status item, popover, and SwiftUI views with TDD around state and formatting.
9. Add the unified application build script and update the root README with clone, build, open, and test commands.
10. Run the full verification matrix while the legacy packages still exist.
11. Delete both legacy package directories only after the new package covers their behavior and passes verification.
12. Run the full verification matrix again after deletion.
13. Push the feature branch, open a pull request to `main`, review its exact file set and checks, and merge only through the pull request.

## README Design

The root README becomes the sole entry point and describes:

- The combined purpose and feature set
- Menu bar indicator meanings
- Overview, History, and Sessions behavior
- The 30-week and per-session Token aggregation semantics
- The read-only local privacy boundary
- macOS 14 and Swift 6 requirements
- HTTPS clone command
- Unified build script command
- `open` command for `CodexMenuBar.app`
- Unified XCTest command
- The fact that prebuilt Releases are not currently provided

No obsolete commands for the two legacy applications remain. A video or GIF is added only in a later change when media is supplied and reviewed for sensitive content.

## Verification Matrix

- Run the new package's complete XCTest suite with zero failures.
- Build the new package in debug mode.
- Build the new package in release mode.
- Run the unified `.app` bundle build script.
- Validate the bundle identifier, version, minimum macOS version, executable, and accessory-app metadata.
- Verify the ad-hoc signature using `codesign --verify --deep --strict`.
- Launch the built application and confirm the process remains alive.
- Open the popover and manually smoke-test Overview, History, Sessions, date selection, session selection, Refresh, Copy Path, dark mode, and Quit.
- Confirm no application cache, database, log, or network activity is introduced.
- Confirm the final Git working tree contains only the unified package, documentation, and intentional supporting files.

## Acceptance Criteria

- The repository builds exactly one maintained application named `CodexMenuBar.app`.
- One menu bar item simultaneously displays primary remaining percentage and live interactive TUI count.
- One SwiftUI popover provides English Overview, History, and Sessions tabs in the approved top-tab layout.
- History displays exactly 30 Monday-based calendar weeks and exact daily Token totals.
- Daily details show all contributing Codex sessions and the five approved Token fields.
- Token history includes all local Codex rollout sources, while live Sessions includes only strict interactive terminal TUIs.
- Session naming follows the approved four-level fallback without displaying other conversation content.
- The application remains local-only, read-only with respect to source data, network-free, and non-controlling.
- Existing usage and session behaviors remain covered by migrated tests.
- Both legacy applications are removed only after the unified application passes the complete verification matrix.
- README clone, build, open, and test commands match the final unified paths and execute successfully.
- All tests, debug/release builds, bundle creation, code-sign verification, and smoke checks pass before the pull request is merged.
