# Codex Menu Bar Tools

Native, local-only macOS menu bar tools for Codex.

- [`codex-usage-menubar`](codex-usage-menubar/README.md): local Codex rate-limit indicator.
- [`codex-session-menubar`](codex-session-menubar/README.md): live interactive Codex CLI TUI monitor.

Each tool is an independent Swift package and `.app` bundle.

## Requirements

- macOS 14 or later
- Xcode 16 or the Swift 6 command-line tools
- A local Codex installation with session data under `~/.codex`

Install Apple's command-line developer tools if needed:

```bash
xcode-select --install
```

## Clone and Run

There are no prebuilt releases yet. Clone the repository and build the apps locally:

```bash
git clone https://github.com/benjaminazz1210/codex-menubar-tools.git
cd codex-menubar-tools
```

Build and open the usage indicator:

```bash
codex-usage-menubar/macos/CodexUsageMenuBar/scripts/build-app.sh
open codex-usage-menubar/macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
```

Build and open the live session monitor:

```bash
codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh
open codex-session-menubar/macos/CodexSessionMenuBar/dist/CodexSessionMenuBar.app
```

Both apps run only in the macOS menu bar and do not show Dock icons. Use each app's menu bar dropdown to refresh or quit it.

## Test

Run the test suites independently from the repository root:

```bash
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
```
