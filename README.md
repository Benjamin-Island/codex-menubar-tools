# Codex Usage Menu Bar

A lightweight SwiftBar plugin for macOS that displays the latest locally reported Codex rate-limit remaining percentage as a native solid template indicator.

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
