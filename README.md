# Codex Menu Bar Tools

Native, local-only macOS menu bar tools for Codex.

- [`codex-usage-menubar`](codex-usage-menubar/README.md): local Codex rate-limit indicator.
- [`codex-session-menubar`](codex-session-menubar/README.md): live interactive Codex CLI TUI monitor.

Each tool is an independent Swift package and `.app` bundle.

## Build

From the repository root:

```bash
codex-usage-menubar/macos/CodexUsageMenuBar/scripts/build-app.sh
codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh
```

Run their tests independently:

```bash
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
```
