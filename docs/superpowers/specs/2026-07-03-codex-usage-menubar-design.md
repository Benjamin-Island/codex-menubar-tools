# Codex Usage Menu Bar Design

Date: 2026-07-03
Status: Approved for planning

## Goal

Build a lightweight macOS menu bar utility that shows the remaining Codex local rate-limit usage using SwiftBar.

The first version is a validation build, not a native macOS app. It should answer one question quickly: "How much Codex usage appears to remain based on the latest locally reported Codex rate-limit event?"

## Scope

In scope:

- A single SwiftBar plugin script.
- Read-only parsing of local Codex session logs.
- Menu bar display of the primary rate-limit window's remaining percentage.
- Dropdown details for primary and secondary windows.
- Conservative error states when usage data is missing or stale.

Out of scope:

- Native macOS app implementation.
- OpenAI Platform API billing, balance, or token-cost tracking.
- ChatGPT account billing pages or browser automation.
- Writes to cache files.
- Network requests.
- Reading `~/.codex/auth.json`.

## Data Source

The plugin reads the latest usable `token_count` event from:

```text
~/.codex/sessions/**/*.jsonl
```

The relevant event shape is:

```text
event_msg.payload.type == "token_count"
```

The script uses:

- `rate_limits.primary.used_percent`
- `rate_limits.primary.window_minutes`
- `rate_limits.primary.resets_at`
- `rate_limits.secondary.used_percent`
- `rate_limits.secondary.window_minutes`
- `rate_limits.secondary.resets_at`
- `rate_limits.plan_type`
- `rate_limits.credits`, when present
- event timestamp

This is a local Codex client log source, not a public stable API. "Real-time" means the latest rate-limit state Codex has reported into local session logs.

## Architecture

The utility is one executable Python script named for SwiftBar refresh behavior:

```text
codex-usage.30s.py
```

SwiftBar runs the script every 30 seconds and renders the script output.

Component boundaries:

- Session discovery: finds candidate `.jsonl` files under `~/.codex/sessions`, ordered from newest to oldest.
- Event parser: scans candidate files from the end and returns the newest valid `token_count` event containing `rate_limits`.
- Usage formatter: converts `used_percent` into remaining percentages.
- SwiftBar renderer: emits the menu bar line, separator, and dropdown lines.

The script does not run shell commands, call the network, write files, import untrusted code, or inspect Codex authentication secrets.

## Display Design

The selected display style is compact percentage.

Menu bar:

```text
Codex 88%
```

The menu bar number is the primary window remaining percentage:

```text
remaining = 100 - rate_limits.primary.used_percent
```

Dropdown:

```text
Codex usage
5h remaining: 88%
7d remaining: 96%
5h resets: 17:20
7d resets: Jul 10 12:30
Plan: plus
Last reported: 12:38:11
Source: local Codex session logs
```

The labels should adapt to the actual `window_minutes` value:

- `300` minutes becomes `5h`
- `10080` minutes becomes `7d`
- Other values are shown as minutes or hours using a simple readable format.

## Color Rules

Use SwiftBar text color parameters when available:

- `>= 50%` remaining: green
- `20%` to `49%` remaining: yellow
- `< 20%` remaining: red
- Unknown state: gray

The dropdown should still show numeric values so color is only an aid, not the only signal.

## Error Handling

The script should fail softly and keep SwiftBar usable.

No session directory:

```text
Codex --
No Codex session directory found
```

No rate-limit event:

```text
Codex --
No rate limit event found yet. Open or use Codex once to generate usage data.
```

Malformed JSON line:

- Skip the line.
- Continue scanning older lines and files.

Missing fields:

- Render the fields that are available.
- Render missing values as `--`.

Permission error:

```text
Codex !
Unable to read Codex session logs
```

Stale data:

- Continue showing the latest known locally reported value.
- Always show `Last reported` in the dropdown so the user can judge freshness.

## Installation

Expected manual install flow:

1. Install SwiftBar if needed:

   ```bash
   brew install swiftbar
   ```

2. Create or choose a SwiftBar plugin directory, for example:

   ```text
   ~/Library/Application Support/SwiftBar/Plugins
   ```

3. Put `codex-usage.30s.py` in that plugin directory.

4. Make it executable:

   ```bash
   chmod +x codex-usage.30s.py
   ```

5. Open SwiftBar and select the plugin directory.

## Acceptance

The first version is acceptable when:

- SwiftBar shows `Codex NN%` in the menu bar when local rate-limit data exists.
- The dropdown shows primary and secondary remaining percentages.
- The dropdown shows reset times and last reported time.
- Missing data shows `Codex --` with a useful explanation.
- The script is read-only with respect to Codex data.
- The script does not read `~/.codex/auth.json`.
- The script does not make network requests.
- The script does not write cache files.

## Follow-Up Options

Possible later improvements:

- Add a small local cache if scanning all session files becomes slow.
- Add a native macOS menu bar app after the SwiftBar version proves useful.
- Add optional display variants, such as dual-window menu bar text.
- Add API billing or cost tracking as a separate feature, if needed.
