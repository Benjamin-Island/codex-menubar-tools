# Codex Usage Menu Bar

A lightweight native macOS menu bar indicator that displays the latest locally reported Codex rate-limit remaining percentage.

## What It Shows

The menu bar displays a compact solid progress indicator with the primary Codex rate-limit window remaining number knocked out inside it:

```text
[solid progress indicator: 88]
```

The dropdown shows:

- Primary window remaining percentage and reset time
- Secondary window remaining percentage and reset time
- Plan type when present in local Codex logs
- Credits status when present in local Codex logs
- Last reported timestamp
- Source note

The value is based on `token_count` events found in local Codex session logs. When Codex reports both the standard `codex` limit and model-specific limits, the app shows the newest standard-limit event; otherwise it falls back to the newest available limit event. It is not an official public usage API.

## Security Boundary

The app:

- Reads `~/.codex/sessions/**/*.jsonl`
- Does not read `~/.codex/auth.json`
- Does not make network requests
- Does not write cache files
- Does not run shell commands

## Native Menu Bar App

Build the native app bundle:

```bash
macos/CodexUsageMenuBar/scripts/build-app.sh
```

The generated app is:

```text
macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
```

Open it:

```bash
open macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
```

The native app is an accessory menu bar app, so it does not show a Dock icon. It refreshes when local Codex session logs change, keeps a 5-second fallback refresh, and provides Refresh and Quit actions from the dropdown menu.

To point the app at a non-default session directory when launching the executable directly:

```bash
CODEX_SESSIONS_DIR="/path/to/sessions" \
  macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app/Contents/MacOS/CodexUsageMenuBar
```

If launching through Finder or `open`, set the environment first:

```bash
launchctl setenv CODEX_SESSIONS_DIR "/path/to/sessions"
open macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
```

## Local Verification

Run focused verification:

```bash
swift build --package-path macos/CodexUsageMenuBar
```

Build the app bundle:

```bash
macos/CodexUsageMenuBar/scripts/build-app.sh
```
