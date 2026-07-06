# Codex Usage Menu Bar

A lightweight macOS menu bar indicator that displays the latest locally reported Codex rate-limit remaining percentage. This repo includes a native AppKit menu bar app and a SwiftBar plugin fallback.

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

The value is based on the newest `token_count` event found in local Codex session logs. It is not an official public usage API.

## Security Boundary

Both implementations:

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

The native app is an accessory menu bar app, so it does not show a Dock icon. It refreshes every 30 seconds, reads the same local Codex session logs as the SwiftBar plugin, and provides Refresh and Quit actions from the dropdown menu.

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

Expected output starts with `| templateImage=...` when local Codex rate-limit data exists. SwiftBar renders the encoded mask using the active macOS menu bar color so it sits with nearby status icons. If there is no local event yet, it still starts with `| templateImage=...` and explains the missing data in the dropdown lines.

Run focused verification:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Expected output:

```text
Ran 5 tests

OK
```
