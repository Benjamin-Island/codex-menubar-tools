# Codex Menu Bar Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the existing usage indicator into a private two-app menu bar tools repository and add a native read-only monitor for live interactive Codex CLI TUI sessions.

**Architecture:** Preserve the existing Git history and usage app while making the current repository the `codex-menubar-tools` root. Build the new app as an independent Swift package with a pure `CodexSessionCore` library for process/log correlation and an AppKit executable for presentation. Discover terminal-attached native Codex processes with libproc, associate each PID with its writable rollout JSONL, and derive one running/stalled snapshot per live top-level TUI.

**Tech Stack:** Apple Swift 6.3, Swift Package Manager, Foundation, AppKit, CoreServices FSEvents, Darwin/libproc, XCTest, Bash app-bundle scripts, Git, GitHub CLI.

## Global Constraints

- Minimum deployment target: macOS 14.
- Native Swift/AppKit only; no Electron, Tauri, or third-party dependencies.
- Monitor only top-level terminal interactive TUI sessions launched as plain `codex`, `codex resume`, or `codex fork`.
- Exclude `exec`, `review`, `app-server`, Codex App, IDE, OpenClaw, MCP servers, automations, and subagents.
- Display only state, task description, and working directory; do not calculate or display durations.
- State has exactly two values: running and stalled, with a five-minute stale threshold.
- The app is read-only: no network, shell commands, credentials, process control, or persistent cache.
- Keep the existing usage app behavior unchanged.
- Keep tracked changes on `feature/codex-menubar-tools-design` until merged through a pull request.
- Never delete `benjaminazz1210/codex-usage-menubar` until the new merged repository and both apps pass fresh verification.

## Target Files

- Root: `README.md`, `.gitignore`, and `docs/superpowers/{specs,plans}`.
- Existing app: `codex-usage-menubar/README.md` and `codex-usage-menubar/macos/CodexUsageMenuBar/...`.
- New core: `SessionModels.swift`, `CodexSessionLogReader.swift`, `InteractiveTUIClassifier.swift`, `DarwinProcessProvider.swift`, and `SessionInventory.swift`.
- New UI: `main.swift`, `StatusController.swift`, `SessionMenuBuilder.swift`, and `SessionDirectoryMonitor.swift`.
- New tests: `CodexSessionCoreTests/...` and `CodexSessionMenuBarTests/SessionMenuBuilderTests.swift`.
- New packaging: `codex-session-menubar/README.md` and `scripts/build-app.sh`.

---

### Task 1: Create and verify the new GitHub baseline

**Files:** No tracked changes.

**Interfaces:**
- Consumes: unchanged local `main` and existing private legacy repository.
- Produces: private `benjaminazz1210/codex-menubar-tools` with `main`; local `origin` points to new and `legacy` points to old.

- [ ] **Step 1: Verify refs, auth, and legacy target**

Run before renaming the remote:

```bash
git status --short --branch
git rev-parse main
git rev-parse origin/main
gh auth status
gh repo view benjaminazz1210/codex-usage-menubar --json nameWithOwner,visibility,defaultBranchRef,url
```

Expected: feature branch is active, local and remote old `main` match, active account is `benjaminazz1210`, and the exact legacy target is private with default branch `main`.

- [ ] **Step 2: Create the private repository without pushing feature work**

```bash
gh repo create benjaminazz1210/codex-menubar-tools --private --description "Native macOS menu bar tools for Codex usage and interactive CLI sessions"
git remote rename origin legacy
git remote add origin git@github.com:benjaminazz1210/codex-menubar-tools.git
git push origin main:main
```

Expected: only unchanged historical `main` is present in the new repository; the feature branch remains local.

- [ ] **Step 3: Verify baseline SHA and remotes**

```bash
git rev-parse main
gh api repos/benjaminazz1210/codex-menubar-tools/commits/main --jq .sha
gh repo view benjaminazz1210/codex-menubar-tools --json visibility,defaultBranchRef,url
git remote -v
```

Expected: local/remote `main` SHAs match, visibility is `PRIVATE`, default branch is `main`, and both remotes resolve correctly. Stop on any mismatch.

---

### Task 2: Rename the local root and organize the usage app

**Files:**
- Move: `README.md` → `codex-usage-menubar/README.md`
- Move: `macos/...` → `codex-usage-menubar/macos/...`
- Modify: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Consumes: existing `CodexUsageMenuBar` package.
- Produces: `/Users/benjaminz/Downloads/codex-menubar-tools` Git root and unchanged nested usage package.

- [ ] **Step 1: Rename the Git root directory**

From `/Users/benjaminz/Downloads`:

```bash
mv codex-usage-menubar codex-menubar-tools
```

Continue from `/Users/benjaminz/Downloads/codex-menubar-tools`.

- [ ] **Step 2: Move tracked usage files**

```bash
mkdir -p codex-usage-menubar
git mv README.md codex-usage-menubar/README.md
git mv macos codex-usage-menubar/macos
```

Keep root `docs/` in place. Update `.gitignore` so both nested packages ignore `.build/` and `dist/`.

- [ ] **Step 3: Add aggregate README**

```markdown
# Codex Menu Bar Tools

Native, local-only macOS menu bar tools for Codex.

- [`codex-usage-menubar`](codex-usage-menubar/README.md): local Codex rate-limit indicator.
- [`codex-session-menubar`](codex-session-menubar/README.md): live interactive Codex CLI TUI monitor.

Each tool is an independent Swift package and `.app` bundle.
```

- [ ] **Step 4: Verify moved usage package**

```bash
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift build --package-path codex-usage-menubar/macos/CodexUsageMenuBar
codex-usage-menubar/macos/CodexUsageMenuBar/scripts/build-app.sh
codesign --verify --deep --strict codex-usage-menubar/macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
git diff --check
```

Expected: zero test failures and all build/signature commands exit 0.

- [ ] **Step 5: Commit organization**

```bash
git add .gitignore README.md codex-usage-menubar
git commit -m "chore: organize codex menu bar tools"
```

---

### Task 3: Add package models and tolerant session-log parsing

**Files:**
- Create: `codex-session-menubar/macos/CodexSessionMenuBar/Package.swift`
- Create: `Sources/CodexSessionCore/SessionModels.swift`
- Create: `Sources/CodexSessionCore/CodexSessionLogReader.swift`
- Create: `Tests/CodexSessionCoreTests/CodexSessionLogReaderTests.swift`

**Interfaces:**
- Produces: `SessionActivity`, `ProcessSnapshot`, `SessionMetadata`, `SessionLogSnapshot`, `SessionDisplaySnapshot`, `SessionInventoryResult`, `ProcessProviding`, and `CodexSessionLogReader`.

- [ ] **Step 1: Write failing parser tests**

Cover named-session priority, first-user-message fallback, directory fallback, metadata source filters, whitespace collapse, Unicode-safe 60-character display, task start/complete, exactly-five-minute staleness, malformed JSON, and incomplete final lines:

```swift
XCTAssertEqual(snapshot.taskDescription, "Renamed task")
XCTAssertEqual(snapshot.activity, .running)
XCTAssertEqual(completed.activity, .stalled)
XCTAssertEqual(exactlyFiveMinutesOld.activity, .stalled)
XCTAssertNil(try reader.readSession(at: nonTUIURL, sessionNames: [:], modifiedAt: now, now: now))
```

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter CodexSessionLogReaderTests
```

Expected: FAIL because the package/core types do not exist.

- [ ] **Step 2: Add manifest and exact public models**

Use library `CodexSessionCore`, executable `CodexSessionMenuBar`, and test targets for core and menu bar:

```swift
public enum SessionActivity: String, Equatable, Sendable { case running, stalled }

public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let userID: UInt32
    public let startedAt: Date
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let hasControllingTerminal: Bool
    public let openFilePaths: [String]
}

public protocol ProcessProviding: Sendable {
    func processSnapshots() throws -> [ProcessSnapshot]
}

public struct SessionMetadata: Equatable, Sendable {
    public let sessionID: String
    public let timestamp: Date
    public let workingDirectory: String
    public let source: String
    public let originator: String
    public let threadSource: String
}

public struct SessionLogSnapshot: Equatable, Sendable {
    public let sessionID: String
    public let workingDirectory: String
    public let taskDescription: String
    public let displayTaskDescription: String
    public let activity: SessionActivity
    public let sourcePath: String
    public let metadataTimestamp: Date
}

public struct SessionDisplaySnapshot: Equatable, Sendable {
    public let pid: Int32
    public let sessionID: String?
    public let activity: SessionActivity
    public let taskDescription: String
    public let displayTaskDescription: String
    public let workingDirectory: String
}

public struct SessionInventoryError: Error, Equatable, Sendable {
    public let message: String
    public let detail: String?
}

public enum SessionInventoryResult: Equatable, Sendable {
    case snapshots([SessionDisplaySnapshot])
    case failure(SessionInventoryError)
}
```

- [ ] **Step 3: Implement parser API**

```swift
public final class CodexSessionLogReader: @unchecked Sendable {
    public func readSessionNames(at indexURL: URL) throws -> [String: String]
    public func readSession(
        at logURL: URL,
        sessionNames: [String: String],
        modifiedAt: Date,
        now: Date
    ) throws -> SessionLogSnapshot?
    public func readMetadata(at logURL: URL) throws -> SessionMetadata?
}
```

Parse only `session_meta`, `event_msg.user_message`, `task_started`, and `task_complete`. Require `source=cli`, `originator=codex-tui`, `thread_source=user`. An unmatched task is running only while `now.timeIntervalSince(modifiedAt) < 300`.

- [ ] **Step 4: Run tests and commit**

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter CodexSessionLogReaderTests
git add codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "feat: parse interactive codex session logs"
```

Expected: parser tests pass with zero failures.

---

### Task 4: Add pure interactive TUI classification

**Files:**
- Create: `Sources/CodexSessionCore/InteractiveTUIClassifier.swift`
- Create: `Tests/CodexSessionCoreTests/InteractiveTUIClassifierTests.swift`

**Interfaces:**
- Consumes: `[ProcessSnapshot]` and current UID.
- Produces: `InteractiveTUIClassifier.candidates(from:currentUID:)`.

- [ ] **Step 1: Write failing classification tests**

```swift
XCTAssertEqual(classify(nativeCodex(arguments: ["codex"])).map(\.pid), [42])
XCTAssertEqual(classify(nativeCodex(arguments: ["codex", "resume", "--last"])).map(\.pid), [42])
XCTAssertEqual(classify(nativeCodex(arguments: ["codex", "fork", "--last"])).map(\.pid), [42])
XCTAssertTrue(classify(nativeCodex(arguments: ["codex", "exec", "echo hi"])).isEmpty)
XCTAssertTrue(classify(nativeCodex(arguments: ["codex", "review"])).isEmpty)
XCTAssertTrue(classify(nativeCodex(hasControllingTerminal: false)).isEmpty)
```

Also test other-user processes; every documented non-TUI subcommand; ChatGPT App, IDE, and OpenClaw server paths; and a Node wrapper/native-child pair returning only the native PID.

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter InteractiveTUIClassifierTests
```

Expected: FAIL because classifier is undefined.

- [ ] **Step 2: Implement whitelist classifier**

```swift
public struct InteractiveTUIClassifier: Sendable {
    public init() {}
    public func candidates(from processes: [ProcessSnapshot], currentUID: UInt32) -> [ProcessSnapshot]
}
```

Require current UID, controlling terminal, and executable basename `codex`; reject Node. Parse global options, allow no subcommand, `resume`, or `fork`, and reject all documented non-TUI commands, including `exec`, `review`, `app-server`, `mcp-server`, `remote-control`, and `exec-server`.

- [ ] **Step 3: Run tests and commit**

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter InteractiveTUIClassifierTests
git add codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "feat: identify interactive codex TUI processes"
```

---

### Task 5: Implement native macOS process and open-file collection

**Files:**
- Create: `Sources/CodexSessionCore/DarwinProcessProvider.swift`
- Create: `Tests/CodexSessionCoreTests/DarwinProcessProviderTests.swift`

**Interfaces:**
- Consumes: macOS libproc and `sysctl`.
- Produces: `DarwinProcessProvider: ProcessProviding`.

- [ ] **Step 1: Write failing provider tests**

Keep system calls behind:

```swift
protocol DarwinProcessReading: Sendable {
    func allPIDs() throws -> [Int32]
    func bsdInfo(pid: Int32) throws -> DarwinBSDInfo
    func executablePath(pid: Int32) throws -> String
    func arguments(pid: Int32) throws -> [String]
    func workingDirectory(pid: Int32) throws -> String?
    func openFiles(pid: Int32) throws -> [String]
}
```

Test C-string/argv decoding, writable rollout-path selection, empty buffers, a PID disappearing between calls, one inaccessible PID being skipped, and a top-level `allPIDs()` failure being returned.

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter DarwinProcessProviderTests
```

Expected: FAIL because provider types are undefined.

- [ ] **Step 2: Implement libproc provider**

Use these APIs:

```swift
proc_listallpids(nil, 0)
proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, MemoryLayout<proc_bsdinfo>.size)
proc_pidpath(pid, &pathBuffer, UInt32(PROC_PIDPATHINFO_MAXSIZE))
proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, MemoryLayout<proc_vnodepathinfo>.size)
proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdBuffer, fdBufferSize)
proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &vnodePath, MemoryLayout<vnode_fdinfowithpath>.size)
```

Read argv via `sysctl([CTL_KERN, KERN_PROCARGS2, pid], ...)`. Set terminal attachment from `PROC_FLAG_CONTROLT` and UID/PPID/start time from `proc_bsdinfo`. Include only `.jsonl` paths under `~/.codex/sessions/` whose `vnode_fdinfowithpath.pfi.fi_openflags & O_ACCMODE` is `O_WRONLY` or `O_RDWR`. Never read file content in this layer.

- [ ] **Step 3: Run tests/build and commit**

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter DarwinProcessProviderTests
swift build --package-path codex-session-menubar/macos/CodexSessionMenuBar
git add codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "feat: inspect codex processes with libproc"
```

---

### Task 6: Correlate live processes into display snapshots

**Files:**
- Create: `Sources/CodexSessionCore/SessionInventory.swift`
- Create: `Tests/CodexSessionCoreTests/SessionInventoryTests.swift`

**Interfaces:**
- Consumes: `ProcessProviding`, classifier, log reader, sessions directory, session-index URL, current UID, and clock.
- Produces: `SessionInventory.read() -> SessionInventoryResult`.

- [ ] **Step 1: Write failing end-to-end core tests**

Cover direct open-file correlation, two PIDs in one cwd, resumed old metadata, fallback within 120 seconds, rejection at 121 seconds, no double-assignment, cached association, PID removal, unassociated TUI fallback, running-first sort, missing directory, and process enumeration failure.

```swift
let inventory = SessionInventory(
    processProvider: FakeProcessProvider([process]),
    classifier: InteractiveTUIClassifier(),
    logReader: CodexSessionLogReader(),
    sessionsDirectory: tempDirectory,
    sessionIndexURL: indexURL,
    currentUID: 501,
    now: { fixedNow }
)
guard case let .snapshots(items) = inventory.read() else {
    return XCTFail("Expected snapshots")
}
XCTAssertEqual(items.map(\.pid), [process.pid])
XCTAssertEqual(items.first?.activity, .running)
```

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter SessionInventoryTests
```

Expected: FAIL because inventory is undefined.

- [ ] **Step 2: Implement correlation and cache**

```swift
public final class SessionInventory: @unchecked Sendable {
    public init(
        processProvider: any ProcessProviding,
        classifier: InteractiveTUIClassifier,
        logReader: CodexSessionLogReader,
        sessionsDirectory: URL,
        sessionIndexURL: URL,
        currentUID: UInt32,
        now: @escaping @Sendable () -> Date = Date.init
    )
    public func read() -> SessionInventoryResult
}
```

Prefer each process's open rollout path. Otherwise reuse a valid in-memory PID association, then scan unassigned metadata with exact cwd equality and timestamp in `[processStart, processStart + 120s]`. An unassociated confirmed TUI remains visible as stalled with directory basename. Remove cached PIDs absent from successful scans. Sort running first, then case-insensitive task, then PID.

- [ ] **Step 3: Run complete core tests and commit**

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
git add codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "feat: build live codex session inventory"
```

---

### Task 7: Build AppKit menu and refresh loop

**Files:**
- Create: `Sources/CodexSessionMenuBar/main.swift`
- Create: `Sources/CodexSessionMenuBar/StatusController.swift`
- Create: `Sources/CodexSessionMenuBar/SessionMenuBuilder.swift`
- Create: `Sources/CodexSessionMenuBar/SessionDirectoryMonitor.swift`
- Create: `Tests/CodexSessionMenuBarTests/SessionMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `SessionInventoryResult`.
- Produces: terminal symbol plus count, read-only menu, immediate/FSEvents/five-second refresh, Refresh, and Quit.

- [ ] **Step 1: Write failing menu tests**

```swift
XCTAssertEqual(menu.items[0].title, "Codex CLI Sessions")
XCTAssertEqual(menu.items[1].title, "1 interactive TUI session")
XCTAssertEqual(menu.items[3].title, "运行中 — Fix login tests")
XCTAssertNil(menu.items[3].action)
XCTAssertEqual(menu.items[4].title, "/tmp/customer-api")
```

Also test plural/empty/error states, running before stalled, full task/path tooltips, and only Refresh/Quit having actions.

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter SessionMenuBuilderTests
```

Expected: FAIL because UI files do not exist.

- [ ] **Step 2: Implement entry point and menu builder**

Use an accessory `NSApplication`. Configure a variable-length `NSStatusItem` with SF Symbol `terminal.fill` and count/`!`. Build each state image with `NSImage(systemSymbolName:accessibilityDescription:)`, apply `NSImage.SymbolConfiguration(paletteColors:)` with `NSColor.systemGreen` or `NSColor.systemYellow`, and set `isTemplate = false`; do not reference a nonexistent `NSMenuItem.contentTintColor`. Session/path rows must have `target == nil` and `action == nil`; preserve full values as tooltips.

- [ ] **Step 3: Implement coalesced refresh and FSEvents**

Use the existing app's `isRefreshing`/`needsRefresh` pattern, perform inventory on a utility queue, update UI on main, run a five-second common-run-loop timer, and monitor the sessions directory with 0.35-second FSEvents debounce. Retry monitor startup after later refreshes if the directory was initially absent.

- [ ] **Step 4: Run tests/build and commit**

```bash
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar --filter SessionMenuBuilderTests
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
swift build --package-path codex-session-menubar/macos/CodexSessionMenuBar
git add codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "feat: add codex session menu bar app"
```

---

### Task 8: Package, document, and fully verify

**Files:**
- Create: `codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh`
- Create: `codex-session-menubar/README.md`
- Modify: root `README.md`

**Interfaces:**
- Produces: `CodexSessionMenuBar.app`, bundle ID `dev.benjamin.codex-session-menubar`, display name `Codex Sessions`, version `0.1.0`, `LSUIElement=true`, macOS 14 minimum.

- [ ] **Step 1: Add executable bundle script**

Mirror the existing script with:

```bash
APP_NAME="CodexSessionMenuBar"
BUNDLE_ID="dev.benjamin.codex-session-menubar"
BUNDLE_NAME="Codex Sessions"
```

Build release, assemble `Contents/MacOS` and `Resources`, generate `Info.plist`, set `LSUIElement` and `NSHighResolutionCapable`, write `PkgInfo`, ad-hoc sign, and run `chmod +x codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh`.

- [ ] **Step 2: Add documentation**

Document displayed fields, strict interactive-TUI scope, process/log inputs, privacy boundary, independent test/build commands, and generated `.app` path. Update root README with both child build commands.

- [ ] **Step 3: Run complete strict verification loop**

```bash
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift build --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift build -c release --package-path codex-usage-menubar/macos/CodexUsageMenuBar
codex-usage-menubar/macos/CodexUsageMenuBar/scripts/build-app.sh
codesign --verify --deep --strict codex-usage-menubar/macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app

swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
swift build --package-path codex-session-menubar/macos/CodexSessionMenuBar
swift build -c release --package-path codex-session-menubar/macos/CodexSessionMenuBar
codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh
codesign --verify --deep --strict codex-session-menubar/macos/CodexSessionMenuBar/dist/CodexSessionMenuBar.app

git diff --check
git status --short
```

Expected: zero failures; all builds and signature checks exit 0. Fix and repeat the entire matrix until green.

- [ ] **Step 4: Run live read-only smoke test**

Add a focused integration test around `DarwinProcessProvider` and `SessionInventory`. It must exit 0, never include `app-server`, and, when a TUI is live, print only PID/activity/cwd—not task content. Skip when no interactive TUI exists. Remove any temporary diagnostic executable before commit.

- [ ] **Step 5: Commit packaging/docs**

```bash
git add README.md codex-session-menubar
git diff --cached --check
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
git commit -m "docs: package codex session menu bar"
```

---

### Task 9: PR, merge, verify, and retire legacy repository

**Files:** No new tracked files unless review feedback requires changes.

**Interfaces:**
- Consumes: fully verified feature branch.
- Produces: merged private new repository; deletes only exact verified legacy repository.

- [ ] **Step 1: Freshly verify branch before publishing**

Run all Task 8 commands again, then:

```bash
git status --short --branch
git log --oneline --decorate main..HEAD
git diff --stat main...HEAD
```

Expected: clean feature branch and only intended commits.

- [ ] **Step 2: Push branch and open PR**

```bash
git push -u origin feature/codex-menubar-tools-design
gh pr create --repo benjaminazz1210/codex-menubar-tools --base main --head feature/codex-menubar-tools-design --title "Add Codex menu bar tools collection" --body "Migrates the existing usage indicator into a two-tool repository and adds a native read-only monitor for live interactive Codex CLI TUI sessions."
```

- [ ] **Step 3: Inspect PR and checks**

```bash
gh pr view --repo benjaminazz1210/codex-menubar-tools --json number,state,baseRefName,headRefName,files,commits,url
gh pr checks --repo benjaminazz1210/codex-menubar-tools
```

Expected: correct base/head/files and all configured checks pass. If none exist, record that and rely on fresh local verification.

- [ ] **Step 4: Merge only through PR**

```bash
gh pr merge --repo benjaminazz1210/codex-menubar-tools --merge --delete-branch=false
git switch main
git pull --ff-only origin main
```

Expected: merged PR and clean local `main` at merge commit.

- [ ] **Step 5: Run hard pre-deletion gate**

```bash
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
codex-usage-menubar/macos/CodexUsageMenuBar/scripts/build-app.sh
codex-session-menubar/macos/CodexSessionMenuBar/scripts/build-app.sh
codesign --verify --deep --strict codex-usage-menubar/macos/CodexUsageMenuBar/dist/CodexUsageMenuBar.app
codesign --verify --deep --strict codex-session-menubar/macos/CodexSessionMenuBar/dist/CodexSessionMenuBar.app
git status --short --branch
git rev-parse HEAD
gh api repos/benjaminazz1210/codex-menubar-tools/commits/main --jq .sha
gh repo view benjaminazz1210/codex-menubar-tools --json visibility,defaultBranchRef,url
gh api repos/benjaminazz1210/codex-menubar-tools/contents --jq '.[].name'
```

Expected: tests/builds/signatures pass; clean `main`; local and remote SHAs match; new repo is private/default `main`; root contains both app directories, `docs`, and `README.md`.

**Hard stop:** Any missing result means do not delete the old repository.

- [ ] **Step 6: Obtain minimum delete scope if absent**

```bash
gh auth status
gh auth refresh -h github.com -s delete_repo
```

Run the refresh only when `delete_repo` is absent.

- [ ] **Step 7: Resolve and delete exact legacy target**

```bash
gh repo view benjaminazz1210/codex-usage-menubar --json nameWithOwner,visibility,url
gh repo delete benjaminazz1210/codex-usage-menubar --yes
```

The resolved name must be exactly `benjaminazz1210/codex-usage-menubar`. Never use a variable, wildcard, owner, or broader target.

- [ ] **Step 8: Verify deletion and final state**

```bash
gh repo view benjaminazz1210/codex-usage-menubar
gh repo view benjaminazz1210/codex-menubar-tools --json nameWithOwner,visibility,defaultBranchRef,url
git remote remove legacy
git remote -v
git status --short --branch
```

Expected: old lookup fails, new lookup succeeds, only new `origin` remains, and local `main` is clean.

---

## Final Requirements Checklist

- [ ] Existing usage app behavior is unchanged and fully green.
- [ ] New app uses Swift/AppKit with no third-party dependencies.
- [ ] Only current-user, terminal-attached, top-level interactive Codex TUI sessions display.
- [ ] Node wrappers and every documented non-TUI source are excluded.
- [ ] Open rollout files are primary PID/session association.
- [ ] Fallback uses exact cwd and 0–120-second window without double assignment.
- [ ] Task fallback is named session → first user message → directory basename.
- [ ] State is exactly running/stalled with five-minute threshold.
- [ ] UI contains only count, state, task, cwd, Refresh, and Quit.
- [ ] No app network, shell execution, credential reads, state writes, or process control.
- [ ] Both packages pass full tests, debug/release builds, bundle builds, and strict signing.
- [ ] New private GitHub repository uses `main` and contains both tools.
- [ ] Feature changes merge through PR.
- [ ] Old repository is deleted only after fresh local and remote verification.
