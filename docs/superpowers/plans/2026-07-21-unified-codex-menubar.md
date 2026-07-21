# Unified Codex Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two existing macOS menu bar applications with one `CodexMenuBar.app` that shows rate limits, 30 weeks of read-only Token history with daily/session details, and live interactive Codex TUI sessions in a SwiftUI popover.

**Architecture:** Build a new Swift Package beside the legacy packages. A Foundation/Darwin `CodexMenuBarCore` target owns tolerant JSONL parsing, an incremental in-memory log index, Token aggregation, rate-limit reduction, and live-process correlation; the `CodexMenuBar` executable owns a main-actor store, one `NSStatusItem`, one `NSPopover`, and thin SwiftUI projections. Port existing behavior under tests, verify the unified app, then remove the two legacy packages.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, Darwin/libproc, AppKit, SwiftUI, CoreServices/FSEvents, XCTest, Bash application-bundle builder.

## Global Constraints

- Minimum operating system is macOS 14.
- Swift tools version is 6.0.
- Product UI is English only.
- Product name is `Codex Menu Bar`; executable and bundle are `CodexMenuBar` and `CodexMenuBar.app`; bundle ID is `dev.benjamin.codex-menubar`.
- Use AppKit only for lifecycle, status item, popover, pasteboard, and filesystem monitoring; use SwiftUI for panel content.
- Add no third-party runtime or test dependencies.
- Read only `~/.codex/sessions/**/*.jsonl`, `~/.codex/session_index.jsonl`, and current-user process metadata/open rollout paths.
- Do not read credentials, access the network, run shell commands at runtime, write caches/databases/logs, or control Codex sessions.
- History contains the current Monday-based calendar week plus the previous 29 weeks and uses system-local event dates.
- History counts every local Codex rollout source; live Sessions remains restricted to top-level interactive terminal TUIs.
- Cached input and Reasoning are detail fields and must never be added again to Total.
- Keep both legacy packages until the unified package passes the pre-removal verification gate.
- Every behavior change uses a witnessed RED test, minimal GREEN implementation, full relevant suite, then refactor.

---

## Planned File Structure

```text
codex-menubar/macos/CodexMenuBar/
├── Package.swift
├── Sources/
│   ├── CodexMenuBarCore/
│   │   ├── TokenUsageModels.swift
│   │   ├── LogIndexModels.swift
│   │   ├── CodexLogParser.swift
│   │   ├── CodexLogIndex.swift
│   │   ├── TokenHistoryAggregator.swift
│   │   ├── RateLimitModels.swift
│   │   ├── RateLimitReducer.swift
│   │   ├── SessionModels.swift
│   │   ├── InteractiveTUIClassifier.swift
│   │   ├── DarwinProcessProvider.swift
│   │   ├── SessionInventory.swift
│   │   ├── DashboardModels.swift
│   │   └── DashboardReader.swift
│   └── CodexMenuBar/
│       ├── main.swift
│       ├── DashboardStore.swift
│       ├── DashboardRouting.swift
│       ├── StatusController.swift
│       ├── StatusItemRenderer.swift
│       ├── SessionDirectoryMonitor.swift
│       ├── PasteboardClient.swift
│       └── Views/
│           ├── DashboardView.swift
│           ├── OverviewView.swift
│           ├── HistoryView.swift
│           ├── SessionsView.swift
│           └── Components.swift
├── Tests/
│   ├── CodexMenuBarCoreTests/
│   │   ├── TokenUsageModelsTests.swift
│   │   ├── CodexLogParserTests.swift
│   │   ├── CodexLogIndexTests.swift
│   │   ├── TokenHistoryAggregatorTests.swift
│   │   ├── RateLimitReducerTests.swift
│   │   ├── InteractiveTUIClassifierTests.swift
│   │   ├── DarwinProcessProviderTests.swift
│   │   ├── SessionInventoryTests.swift
│   │   ├── DashboardReaderTests.swift
│   │   └── LiveDashboardSmokeTests.swift
│   └── CodexMenuBarTests/
│       ├── DashboardRoutingTests.swift
│       ├── DashboardStoreTests.swift
│       ├── StatusItemPresentationTests.swift
│       └── DashboardViewSmokeTests.swift
└── scripts/build-app.sh
```

## Task 1: Scaffold the Unified Package and Token Value Types

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Package.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/TokenUsageModels.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/main.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/TokenUsageModelsTests.swift`

**Interfaces:**
- Produces: `TokenCounts`, `SessionIdentity`, `TokenEvent`, `SessionDayUsage`, `DailyUsage`, and `TokenHistorySnapshot`.
- `TokenCounts` is the single arithmetic value type consumed by parser, aggregator, dashboard, and UI tasks.

- [ ] **Step 1: Add the package manifest and empty executable shell**

Create a macOS 14 package with library `CodexMenuBarCore`, executable `CodexMenuBar`, and the two XCTest targets shown in Planned File Structure. The executable shell must contain only the accessory `NSApplication` startup needed to let SwiftPM link; it must not yet create a status item.

Run:

```bash
swift build --package-path codex-menubar/macos/CodexMenuBar
```

Expected: PASS with an empty `CodexMenuBarCore` marker and linked executable.

- [ ] **Step 2: Write the failing Token arithmetic test**

Create this first test:

```swift
func testDeltaRestartsOnlyFieldsThatDecrease() {
    let previous = TokenCounts(total: 100, input: 80, cachedInput: 30, output: 20, reasoning: 5)
    let current = TokenCounts(total: 140, input: 10, cachedInput: 35, output: 30, reasoning: 2)

    XCTAssertEqual(
        current.increment(since: previous),
        TokenCounts(total: 40, input: 10, cachedInput: 5, output: 10, reasoning: 2)
    )
}
```

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter TokenUsageModelsTests
```

Expected: FAIL because `TokenCounts` does not exist.

- [ ] **Step 3: Implement the minimal arithmetic model**

Implement this public shape:

```swift
public struct TokenCounts: Equatable, Sendable, Codable {
    public let total: Int64
    public let input: Int64
    public let cachedInput: Int64
    public let output: Int64
    public let reasoning: Int64

    public static let zero = TokenCounts(total: 0, input: 0, cachedInput: 0, output: 0, reasoning: 0)

    public func increment(since previous: TokenCounts?) -> TokenCounts {
        func delta(_ current: Int64, _ old: Int64?) -> Int64 {
            guard let old, current >= old else { return max(0, current) }
            return current - old
        }
        return TokenCounts(
            total: delta(total, previous?.total),
            input: delta(input, previous?.input),
            cachedInput: delta(cachedInput, previous?.cachedInput),
            output: delta(output, previous?.output),
            reasoning: delta(reasoning, previous?.reasoning)
        )
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            total: lhs.total + rhs.total,
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }
}
```

Add immutable models with these exact stored properties:

```swift
public struct SessionIdentity: Hashable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let workingDirectory: String?
    public let sourceKind: String
}

public struct TokenEvent: Equatable, Sendable {
    public let timestamp: Date
    public let cumulative: TokenCounts
    public let sequence: Int
}

public struct SessionDayUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let session: SessionIdentity
    public let counts: TokenCounts
}

public struct DailyUsage: Identifiable, Equatable, Sendable {
    public let id: Date
    public let date: Date
    public let counts: TokenCounts
    public let sessions: [SessionDayUsage]
    public let heatLevel: Int
    public let isFuture: Bool
}

public struct TokenHistorySnapshot: Equatable, Sendable {
    public let interval: DateInterval
    public let days: [DailyUsage]
    public let selectedDefaultDate: Date
}
```

- [ ] **Step 4: Verify GREEN and arithmetic edge cases**

Add tests for zero, equal counters, first event from zero, and independent field reset. Run the focused suite, then:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: all new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: scaffold unified Codex menu bar core"
```

## Task 2: Parse One Rollout into an Indexed Session Record

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/LogIndexModels.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/CodexLogParser.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/CodexLogParserTests.swift`

**Interfaces:**
- Consumes: `TokenCounts`, `TokenEvent`, and `SessionIdentity` from Task 1.
- Produces: `IndexedSessionLog`, `LifecycleSummary`, `RateLimitCandidate`, `ParseWarning`, `CodexLogParser.parse(logURL:sessionNames:modifiedAt:)`, and `CodexLogParser.readSessionNames(at:)`.

- [ ] **Step 1: Write a failing realistic JSONL parser test**

The fixture must contain `session_meta`, first `user_message`, two cumulative `token_count` records, `task_started`, one malformed line, and no `task_complete`. Assert:

```swift
XCTAssertEqual(log.session.id, "session-1")
XCTAssertEqual(log.session.name, "Named thread")
XCTAssertEqual(log.session.workingDirectory, "/tmp/project")
XCTAssertEqual(log.session.sourceKind, "cli")
XCTAssertEqual(log.tokenEvents.map(\.cumulative.total), [100, 160])
XCTAssertEqual(log.lifecycle, .active)
XCTAssertEqual(log.warnings.count, 1)
```

Use `thread_name` from an injected `sessionNames` dictionary to prove it wins over the first user message.

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter CodexLogParserTests
```

Expected: FAIL because parser/index models are absent.

- [ ] **Step 2: Define parser output models**

Implement these exact public contracts:

```swift
public enum LifecycleSummary: Equatable, Sendable { case active, inactive }

public struct ParseWarning: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let message: String
}

public struct RawRateLimitWindow: Equatable, Sendable {
    public let usedPercent: Double?
    public let windowMinutes: Double?
    public let resetsAt: Double?
}

public struct RawCredits: Equatable, Sendable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: Int?
}

public struct RateLimitCandidate: Equatable, Sendable {
    public let limitID: String?
    public let primary: RawRateLimitWindow?
    public let secondary: RawRateLimitWindow?
    public let credits: RawCredits?
    public let planType: String?
    public let reportedAt: Date?
    public let fileModifiedAt: Date
    public let sequence: Int
    public let sourcePath: String
}

public struct IndexedSessionLog: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let session: SessionIdentity
    public let metadataTimestamp: Date?
    public let tokenEvents: [TokenEvent]
    public let rateLimits: [RateLimitCandidate]
    public let lifecycle: LifecycleSummary
    public let warnings: [ParseWarning]
}
```

`RawRateLimitWindow` and `RawCredits` preserve tolerant decoded values without introducing presentation labels into the parser. Task 5 maps these raw values into `WindowUsage` and the final credits description.

- [ ] **Step 3: Implement tolerant one-pass parsing**

`CodexLogParser` must read the file once, split preserving an incomplete final line, decode records independently, and collect session metadata, only the first normalized user message, lifecycle state, Token events, and rate-limit candidates. Implement session naming as:

```swift
let fullName = sessionNames[sessionID]
    ?? firstUserMessage
    ?? workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
    ?? "Untitled session"
let displayName = String(fullName.prefix(60))
```

When session metadata has no ID, use the standardized rollout path as the stable fallback ID so valid Token events still participate in History. Replace the simple prefix with the legacy Unicode-safe `SessionTextFormatting.displayDescription` when Session models migrate in Task 6. Token values must decode integers, finite doubles, and numeric strings into nonnegative `Int64`; invalid, negative, nonfinite, and oversized values become zero for that field without dropping the record.

- [ ] **Step 4: Expand RED/GREEN coverage**

Add focused tests, one behavior each, for:

- Thread name, first message, directory, and `Untitled session` fallbacks.
- Whitespace normalization.
- Missing timestamp excludes a Token event but retains a rate-limit candidate.
- Malformed and incomplete final lines do not discard earlier records.
- Unknown source becomes `Other`.
- `task_complete` after `task_started` produces `.inactive`.
- Input/Cached/Output/Reasoning fields remain independent.

Run the focused suite and complete new-package suite. Expected: PASS with no warnings from Swift.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: parse unified Codex rollout records"
```

## Task 3: Aggregate Exactly 30 Weeks of Daily and Per-Session Usage

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/TokenHistoryAggregator.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/TokenHistoryAggregatorTests.swift`

**Interfaces:**
- Consumes: `[IndexedSessionLog]`, `Calendar`, and `now`.
- Produces: `TokenHistoryAggregator.makeHistory(logs:calendar:now:) -> TokenHistorySnapshot`.

- [ ] **Step 1: Write the failing cumulative-delta test**

Create one session with cumulative Totals 100, 160, duplicate 160, then reset 20 on the same day. Assert the daily Total is `180`, not `440`, and each category uses the same independent-delta rule.

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter TokenHistoryAggregatorTests/testCumulativeEventsBecomeNonDuplicatedDailyIncrements
```

Expected: FAIL because `TokenHistoryAggregator` is absent.

- [ ] **Step 2: Implement interval and accumulation**

Use this algorithm:

```swift
public func makeHistory(
    logs: [IndexedSessionLog],
    calendar inputCalendar: Calendar,
    now: Date
) -> TokenHistorySnapshot {
    var calendar = inputCalendar
    calendar.firstWeekday = 2
    let today = calendar.startOfDay(for: now)
    let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)!
    let start = calendar.date(byAdding: .weekOfYear, value: -29, to: currentWeek.start)!
    let end = calendar.date(byAdding: .day, value: 7, to: currentWeek.start)!
    let interval = DateInterval(start: start, end: end)

    var byDay: [Date: [String: TokenCounts]] = [:]
    for log in logs {
        var previous: TokenCounts?
        for event in log.tokenEvents.sorted(by: eventOrder) {
            let increment = event.cumulative.increment(since: previous)
            previous = event.cumulative
            let day = calendar.startOfDay(for: event.timestamp)
            guard interval.contains(day) else { continue }
            byDay[day, default: [:]][log.session.id, default: .zero] =
                byDay[day, default: [:]][log.session.id, default: .zero] + increment
        }
    }
    return makeSnapshot(interval: interval, today: today, byDay: byDay, logs: logs, calendar: calendar)
}
```

`eventOrder` compares timestamp then sequence. `makeSnapshot` must emit exactly 210 ordered days, mark dates after today as future, sort session rows by descending Total/name, calculate daily sums, and assign heat levels after daily Totals are known.

- [ ] **Step 3: Implement quartile heat levels under tests**

Write the failing test first for zero plus four nonzero quartile levels. Implement `heatLevel(total:thresholds:)` so zero/future is 0 and positive values map to 1...4 using the 25th, 50th, and 75th percentile values of visible nonzero totals. Exact date and count remain in the model regardless of level collapse.

- [ ] **Step 4: Expand calendar and source tests**

Add separate tests for:

- Monday start and exactly 30 columns/210 cells.
- Current-week future dates disabled.
- Cross-midnight events attributed to separate local dates.
- DST transition using a calendar with `America/Los_Angeles`.
- Calendar year boundary.
- A session spanning days appears with day-specific increments.
- Interactive, exec, IDE/App, and Other sessions all contribute.
- Daily sessions sort by Total descending and name on ties.

Run focused and complete suites; expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: aggregate thirty weeks of token history"
```

## Task 4: Add the Incremental Read-Only Log Index

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/CodexLogIndex.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/CodexLogIndexTests.swift`

**Interfaces:**
- Consumes: sessions directory, session index URL, required live rollout paths, and `CodexLogParser`.
- Produces: `LogIndexSnapshot` and mutable-in-memory `CodexLogIndex.refresh(...)`.

- [ ] **Step 1: Write a failing reuse/change/delete test**

Inject a `LogParsing` spy and a `LogFileDiscovering` fake. First refresh exposes A and B, second refresh keeps A fingerprint and changes B, third deletes A. Assert parse calls are `[A,B]`, then `[B]`, then `[]`, and the final snapshot contains only B.

Run the focused test. Expected: FAIL because index protocols/types are absent.

- [ ] **Step 2: Define exact index contracts**

```swift
public struct LogFileFingerprint: Hashable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let byteSize: Int64
}

public struct LogIndexSnapshot: Equatable, Sendable {
    public let logs: [IndexedSessionLog]
    public let warnings: [ParseWarning]
}

public protocol LogParsing: Sendable {
    func parse(logURL: URL, sessionNames: [String: String], modifiedAt: Date) throws -> IndexedSessionLog
    func readSessionNames(at indexURL: URL) throws -> [String: String]
}

public protocol LogFileDiscovering: Sendable {
    func fingerprints(in sessionsDirectory: URL, modifiedSince: Date, requiredPaths: Set<String>) throws -> [LogFileFingerprint]
}
```

`CodexLogIndex` stores `[String: (fingerprint, log)]` in memory and never serializes it.

- [ ] **Step 3: Implement refresh and partial warnings**

Refresh reads session names once, discovers candidates, reuses exact fingerprints, reparses changed files, retains successful files when one new parse fails only for that refresh, removes paths absent from a successful discovery, and returns warnings for individual failures. A top-level discovery failure must throw instead of returning a misleading empty snapshot.

- [ ] **Step 4: Add boundary tests**

Cover new file, changed byte size with same date, changed date with same size, required old live path, missing session index, unreadable single file, top-level directory denial, and complete in-memory reset after constructing a new index instance.

Run focused and full suites; expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: index Codex logs incrementally in memory"
```

## Task 5: Migrate Rate-Limit Behavior onto Indexed Logs

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitModels.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitReducer.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/RateLimitReducerTests.swift`
- Reference during port: `codex-usage-menubar/macos/CodexUsageMenuBar/Tests/CodexUsageCoreTests/CodexLogReaderTests.swift`

**Interfaces:**
- Consumes: `[IndexedSessionLog]` and their `RateLimitCandidate` values.
- Produces: existing-compatible `WindowUsage`, `UsageSnapshot`, `UsageReadError`, `UsageReadResult`, and `RateLimitReducer.reduce(logs:)`.

- [ ] **Step 1: Port tests before implementation and witness RED**

Port the legacy formatting and rate-limit selection assertions into `RateLimitReducerTests`, changing fixtures to construct indexed candidates rather than reread directories. Preserve coverage for canonical `limit_id == "codex"`, named fallback, timestamp ordering across files, file-date fallback, malformed numeric values, credits, missing events, and all formatting helpers.

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter RateLimitReducerTests
```

Expected: FAIL because `RateLimitReducer` and final models are absent.

- [ ] **Step 2: Move the proven public models and tolerant formatting**

Move the semantic content of legacy `UsageModels.swift` into `RateLimitModels.swift`, retaining finite-number guards and English labels. Change no approved calculation behavior.

- [ ] **Step 3: Implement indexed candidate reduction**

Implement candidate ordering exactly:

```swift
private func isNewer(_ lhs: RateLimitCandidate, than rhs: RateLimitCandidate?) -> Bool {
    guard let rhs else { return true }
    let lhsCanonical = lhs.limitID == "codex"
    let rhsCanonical = rhs.limitID == "codex"
    if lhsCanonical != rhsCanonical { return lhsCanonical }
    let lhsDate = lhs.reportedAt ?? lhs.fileModifiedAt
    let rhsDate = rhs.reportedAt ?? rhs.fileModifiedAt
    if lhsDate != rhsDate { return lhsDate > rhsDate }
    if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
    return lhs.sequence > rhs.sequence
}
```

Return `--` for no candidate and `!` only for top-level log-index failure, keeping partial warnings separate from a usable snapshot.

- [ ] **Step 4: Run migrated and legacy suites**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter RateLimitReducerTests
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
```

Expected: both PASS with matching behavioral assertions.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: migrate Codex rate limit reduction"
```

## Task 6: Migrate Interactive TUI Discovery and Indexed Session Inventory

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/SessionModels.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/InteractiveTUIClassifier.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/DarwinProcessProvider.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/SessionInventory.swift`
- Create: corresponding three test files plus `LiveDashboardSmokeTests.swift`
- Reference during port: all files under `codex-session-menubar/macos/CodexSessionMenuBar/Sources/CodexSessionCore/` and `Tests/CodexSessionCoreTests/`

**Interfaces:**
- Consumes: process snapshots, `LogIndexSnapshot`, session names already resolved by parser, current UID, and `now`.
- Produces: `SessionDisplaySnapshot` with PID, ID, activity, names, path, last update, cumulative Token counts, and source path.

- [ ] **Step 1: Port classifier/provider tests and witness RED**

Copy the semantic cases from `InteractiveTUIClassifierTests.swift` and `DarwinProcessProviderTests.swift` into the new test target, importing `CodexMenuBarCore`. Run both filters before adding production files.

Expected: FAIL with missing `ProcessSnapshot`, `InteractiveTUIClassifier`, and `DarwinProcessProvider`.

- [ ] **Step 2: Port process models, classifier, and provider with no behavior expansion**

Preserve exact allowed subcommands, excluded subcommands/path markers, current-user/terminal checks, wrapper handling, writable-session-log filtering, and process-disappearance tolerance. Change user-facing errors to English while leaving comparison and inclusion rules unchanged.

Run the two focused suites; expected: PASS.

- [ ] **Step 3: Write indexed inventory RED tests**

Port the legacy `SessionInventoryTests` cases, but supply `[IndexedSessionLog]` instead of making the inventory reread JSONL. Add assertions for `lastUpdatedAt`, `sourcePath`, and the associated log's latest cumulative Token counts.

Use this exact output extension:

```swift
public struct SessionDisplaySnapshot: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let sessionID: String?
    public let activity: SessionActivity
    public let taskDescription: String
    public let displayTaskDescription: String
    public let workingDirectory: String
    public let sourcePath: String?
    public let lastUpdatedAt: Date?
    public let tokenCounts: TokenCounts
}
```

Run the inventory filter. Expected: FAIL because the indexed inventory API is absent.

- [ ] **Step 4: Implement indexed correlation**

Expose:

```swift
public func read(
    logs: [IndexedSessionLog],
    now: Date
) -> SessionInventoryResult
```

Prefer a candidate process's writable open rollout path. Otherwise reuse a valid in-memory PID association. Otherwise match an unassigned top-level interactive indexed log whose working directory equals the process cwd and metadata timestamp lies in `[process.startedAt, process.startedAt + 120 seconds]`, selecting the closest timestamp. A confirmed TUI without a match remains visible as Stalled with directory fallback and zero Token counts. Remove cached PIDs absent from a successful scan.

- [ ] **Step 5: Run new and legacy session suites**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter InteractiveTUIClassifierTests
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DarwinProcessProviderTests
swift test --package-path codex-menubar/macos/CodexMenuBar --filter SessionInventoryTests
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
```

Expected: all PASS; the live smoke test may skip only when platform permissions make enumeration unavailable, matching existing semantics.

- [ ] **Step 6: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: migrate live Codex session inventory"
```

## Task 7: Compose Independent Dashboard Subsystem States

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/DashboardModels.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/DashboardReader.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/DashboardReaderTests.swift`

**Interfaces:**
- Consumes: `CodexLogIndex`, `TokenHistoryAggregator`, `RateLimitReducer`, `SessionInventory`, paths, calendar, UID, and clock.
- Produces: `DashboardSnapshot` with independent `rateLimit`, `history`, and `sessions` states plus warnings and timestamp.

- [ ] **Step 1: Write independent-failure RED tests**

Define expectations before implementation:

```swift
XCTAssertEqual(snapshot.rateLimit, .content(expectedUsage))
XCTAssertEqual(snapshot.history, .content(expectedHistory))
XCTAssertEqual(snapshot.sessions, .failure(expectedProcessError))
```

Add the converse directory-failure case where Sessions process discovery succeeds but Usage/History fail. Run the focused suite; expected: FAIL.

- [ ] **Step 2: Define state models**

```swift
public enum ContentState<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case content(Value)
    case empty(String)
    case failure(DashboardError)
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let rateLimit: ContentState<UsageSnapshot>
    public let history: ContentState<TokenHistorySnapshot>
    public let sessions: ContentState<[SessionDisplaySnapshot]>
    public let warnings: [DashboardWarning]
    public let updatedAt: Date
}
```

Implement explicit English `DashboardError` and `DashboardWarning` messages suitable for the UI.

- [ ] **Step 3: Implement one background read pipeline**

The reader must discover process candidates first to collect required live rollout paths, refresh the index once, then reduce rate limit/history/sessions from that same immutable index snapshot. Catch directory/index and process errors separately. Partial file warnings accompany content rather than replacing it.

- [ ] **Step 4: Cover missing/empty/partial states**

Add tests for missing sessions directory, no Token events, no live sessions, one unreadable file, successful next refresh after error, and exact updated time from an injected clock. Run focused and full new-package suites; expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: compose unified dashboard snapshots"
```

## Task 8: Implement Main-Actor Routing, Refresh Coalescing, and Pasteboard Behavior

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/DashboardRouting.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/DashboardStore.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PasteboardClient.swift`
- Create: corresponding three app-target test files, with pasteboard cases in `DashboardStoreTests.swift`

**Interfaces:**
- Produces: `DashboardTab`, `HistorySelection`, `DashboardStore`, `PasteboardWriting`, and `DashboardStore.refresh()`.
- Consumes: an injected asynchronous `DashboardReading` closure and immutable `DashboardSnapshot`.

- [ ] **Step 1: Write routing RED tests**

Test that selecting an Overview heatmap day sets tab History and selected date; selecting an Overview live session sets tab Sessions and PID; selecting a daily session sets `.session(date:sessionID:)`; Back to Day restores `.day(date:)`.

- [ ] **Step 2: Implement routing state**

```swift
enum DashboardTab: String, CaseIterable { case overview, history, sessions }
enum HistorySelection: Equatable { case day(Date), session(date: Date, sessionID: String) }

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot
    @Published var selectedTab: DashboardTab = .overview
    @Published var historySelection: HistorySelection
    @Published var selectedSessionPID: Int32?
    @Published private(set) var isRefreshing = false
}
```

All route mutations are synchronous main-actor methods with exact intent names: `showHistory(date:)`, `showHistoricalSession(date:sessionID:)`, `showDay(_:)`, and `showLiveSession(pid:)`.

- [ ] **Step 3: Write refresh-coalescing RED test**

Use a suspended async fake. Call `refresh()` three times while the first is pending. Assert the reader is invoked twice total: current plus one queued follow-up. Assert the old successful snapshot remains visible while `isRefreshing` is true.

- [ ] **Step 4: Implement coalescing and clipboard injection**

Use `refreshTask != nil` and `needsRefresh` flags. The second and later overlapping requests set only `needsRefresh`. On completion, clear the task, apply the snapshot, and start one follow-up if requested.

Define:

```swift
protocol PasteboardWriting { func write(_ string: String) }
```

Production implementation uses `NSPasteboard.general.clearContents()` then `setString(_:forType:.string)`. Test that Copy Path writes exactly the selected working directory and nothing for an unmatched PID.

- [ ] **Step 5: Run app-state and full suites**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardRoutingTests
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardStoreTests
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: add unified dashboard state and routing"
```

## Task 9: Build the Combined Status Item, Popover, and SwiftUI Views

**Files:**
- Create: remaining files under `Sources/CodexMenuBar/` and `Sources/CodexMenuBar/Views/`
- Create: `Tests/CodexMenuBarTests/StatusItemPresentationTests.swift`
- Create: `Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`

**Interfaces:**
- Consumes: `DashboardStore` and all immutable core snapshots.
- Produces: one variable-width status item, one 620x520 transient popover, English top tabs, Overview/History/Sessions screens, footer actions, and accessibility labels.

- [ ] **Step 1: Write status-item presentation RED tests**

Create a pure model builder and assert:

```swift
XCTAssertEqual(
    StatusItemPresentation.make(remainingPercent: 72, sessionCount: 3),
    .init(usageLabel: "72", progress: 0.72, sessionLabel: "3", accessibilityValue: "72 percent remaining, 3 interactive sessions")
)
```

Also cover missing usage (`--`), rate error (`!`), clamped percentage, and zero sessions. Run filter; expected: FAIL.

- [ ] **Step 2: Implement status presentation and renderer**

Reuse the proven battery-sized drawing from legacy `UsageIndicatorRenderer`, append an SF Symbol `terminal.fill` and count through the `NSStatusItem` button image/title combination, and use the pure presentation model for all strings. Error status changes the usage label only; it does not hide the session count.

- [ ] **Step 3: Write SwiftUI hosting RED smoke tests**

For each root state (loading, full content, empty, independent failure), construct `DashboardView(store:)` inside `NSHostingController`, lay it out at 620x520, and assert finite nonzero fitting size. The test must fail first because views do not exist.

- [ ] **Step 4: Implement thin SwiftUI projections**

Implement:

- `DashboardView`: header, top `Overview / History / Sessions N` picker, selected page, footer.
- `OverviewView`: three cards, compact heatmap, live-session summary; route clicks through store methods.
- `HistoryView`: 7x30 Monday-first grid, hover/accessibility labels, day/session detail state, Back to Day.
- `SessionsView`: Running-before-Stalled cards and selected live detail.
- `Components.swift`: `UsageCard`, `HeatmapGrid`, `TokenBreakdown`, `SessionRow`, `LoadingPanel`, `EmptyPanel`, `ErrorPanel`, and `PartialWarningBanner`.

Views may format only presentation strings. Selection, sorting, counting, and error semantics must remain in tested store/core models. Use system colors/materials, no hard-coded light-only colors, and pair every status color with text and icon.

- [ ] **Step 5: Implement AppKit host and monitoring**

`StatusController` creates `NSStatusItem.variableLength`, a `.transient` `NSPopover`, and an `NSHostingController(rootView: DashboardView(store: store))`; clicking the status button toggles the popover. Set content size to 620x520. Port the existing FSEvents monitor with 0.35-second debounce and five-second timer fallback. App launch resolves `CODEX_SESSIONS_DIR` and `CODEX_SESSION_INDEX` overrides before standard paths.

- [ ] **Step 6: Run focused, full, debug, and release checks**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter CodexMenuBarTests
swift test --package-path codex-menubar/macos/CodexMenuBar
swift build --package-path codex-menubar/macos/CodexMenuBar
swift build -c release --package-path codex-menubar/macos/CodexMenuBar
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar
git commit -m "feat: add SwiftUI Codex dashboard popover"
```

## Task 10: Add Bundle Build, Rewrite README, and Pass the Pre-Removal Gate

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/scripts/build-app.sh`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `codex-usage-menubar/V2EX_POST.md`

**Interfaces:**
- Produces: `codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app`.

- [ ] **Step 1: Add the deterministic app-bundle script**

Adapt the existing builder with exact identity values from Global Constraints. Build release, copy executable to `Contents/MacOS/CodexMenuBar`, write Info.plist with version `0.2.0`, build `1`, minimum `14.0`, and `LSUIElement=true`, then ad-hoc sign. Add new `.build/` and `dist/` paths to `.gitignore`.

- [ ] **Step 2: Rewrite README for one app**

Document product purpose, combined indicator, three pages, Token semantics, read-only privacy, requirements, HTTPS clone, unified build/open/test commands, and absence of prebuilt Releases. Remove both legacy build/open commands. Update the V2EX draft to describe the unified app and retain explicit download/screenshot placeholders only in its private publishing checklist.

- [ ] **Step 3: Verify every documented command**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
open codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
```

Expected: tests PASS, build prints the `.app` path, and one `CodexMenuBar` process stays alive.

- [ ] **Step 4: Run the complete pre-removal matrix**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
swift test --package-path codex-usage-menubar/macos/CodexUsageMenuBar
swift test --package-path codex-session-menubar/macos/CodexSessionMenuBar
swift build -c release --package-path codex-menubar/macos/CodexMenuBar
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
plutil -lint codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app/Contents/Info.plist
```

Expected: all commands exit 0; unified tests include every migrated legacy behavior.

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md codex-usage-menubar/V2EX_POST.md codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
git commit -m "docs: document unified Codex menu bar"
```

## Task 11: Remove Legacy Applications and Perform Final Verification

**Files:**
- Delete: `codex-usage-menubar/`
- Delete: `codex-session-menubar/`
- Verify: all unified source, tests, documentation, and build outputs.

**Interfaces:**
- Produces: repository with exactly one maintained application package.

- [ ] **Step 1: Prove migrated test coverage before deletion**

Map every legacy XCTest method name to a new-package XCTest method or an intentionally stronger replacement. Save this mapping in the implementation commit message body or PR description. Do not delete legacy files if any case lacks coverage.

- [ ] **Step 2: Remove only the two exact legacy directories**

Use explicit paths after verifying the current working directory and branch. Do not remove repository root, unrelated docs, or generated user files.

- [ ] **Step 3: Run final fresh verification**

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
swift build --package-path codex-menubar/macos/CodexMenuBar
swift build -c release --package-path codex-menubar/macos/CodexMenuBar
codex-menubar/macos/CodexMenuBar/scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app
plutil -lint codex-menubar/macos/CodexMenuBar/dist/CodexMenuBar.app/Contents/Info.plist
git diff --check
git status --short
```

Expected: every command exits 0; Git status contains only intentional tracked deletion/addition changes and no generated `.build`, `dist`, or `.superpowers` files.

- [ ] **Step 4: Manual UI and privacy smoke test**

Verify menu bar combined indicator, popover open/close, all three tabs, 30-week grid, today selection, historical session drill-down/back, live session selection, Copy Path, Refresh, dark mode, Quit, missing-directory override, and one malformed fixture. Inspect process/network/file activity sufficiently to confirm no runtime cache/database/log or network client was introduced.

- [ ] **Step 5: Commit deletion and final migration**

```bash
git add README.md .gitignore codex-menubar docs codex-usage-menubar codex-session-menubar
git commit -m "feat: replace legacy menu bar apps with unified dashboard"
```

- [ ] **Step 6: Push, open PR, review, and merge**

```bash
git push -u origin feature/unified-codex-menubar
gh pr create --base main --head feature/unified-codex-menubar --title "feat: unify Codex menu bar tools" --body-file /tmp/unified-codex-menubar-pr.md
gh pr checks --watch
```

PR description must summarize features, privacy boundary, migrated test count, exact verification commands/results, and intentional deletion of both legacy packages. Review the PR file list and mergeability. Merge only through the PR after checks and review are satisfactory, then verify local `main` matches `origin/main`.

## Plan Self-Review Results

- Spec coverage: every goal, non-goal, privacy constraint, UI choice, Token rule, migration gate, README requirement, and verification item maps to Tasks 1-11.
- Scope: tasks form one dependency chain that produces one application; no independent release/signing/video subsystem is included.
- Type consistency: `TokenCounts`, `IndexedSessionLog`, `LogIndexSnapshot`, `DashboardSnapshot`, `SessionDisplaySnapshot`, and `DashboardStore` names and consumers are consistent across tasks.
- TDD: every behavioral task begins with a focused failing test and requires witnessed RED before production implementation.
- Destructive gate: legacy directories are deleted only in Task 11 after the explicit pre-removal matrix and coverage mapping pass.
