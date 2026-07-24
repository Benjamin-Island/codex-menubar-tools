# Today Initial Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Today initial: <percent>%` to each Usage card, with an optional ` · reset today` marker backed by the earliest valid local-day rate-limit observation.

**Architecture:** Extend the incremental JSONL accumulator with one bounded, mergeable daily rate-limit trace per log. The reducer combines same-family traces using the dashboard's injected calendar and clock, enriches `WindowUsage`, and exposes a pure formatter that the SwiftUI card renders.

**Tech Stack:** Swift 6, Foundation, SwiftUI, XCTest, Swift Package Manager

## Global Constraints

- Display remaining percentage, calculated with the existing `UsageFormatting.remainingFromUsed` rule.
- Exact normal copy: `Today initial: 50%`.
- Exact reset copy: `Today initial: 50% · reset today`.
- Do not repeat the current remaining percentage or calculate daily percentage-point consumption.
- Primary and Secondary calculate initial values and reset state independently.
- Use the injected local `Calendar`; do not group days with fixed UTC arithmetic.
- Missing timestamps, invalid percentages, and non-today observations do not establish a baseline.
- Only differing non-nil `resets_at` values establish reset evidence.
- Preserve canonical `limit_id == "codex"` priority over fallback limit IDs.
- Keep data bounded; do not retain every Usage event or add app-owned persistence.
- Use RED-GREEN-REFACTOR for every production behavior.

---

## File Structure

- `Sources/CodexMenuBarCore/LogIndexModels.swift`: immutable daily trace types exposed by `SessionLogSummary`.
- `Sources/CodexMenuBarCore/SessionLogAccumulator.swift`: bounded per-log daily trace construction and midnight pruning.
- `Sources/CodexMenuBarCore/RateLimitModels.swift`: Today fields on `WindowUsage` and exact display formatting.
- `Sources/CodexMenuBarCore/RateLimitReducer.swift`: same-family trace selection, earliest observation selection, and reset merging.
- `Sources/CodexMenuBarCore/DashboardReader.swift`: inject the reader's calendar and clock into reduction.
- `Sources/CodexMenuBar/Views/Components.swift`: conditionally render the Today line.
- `Tests/CodexMenuBarCoreTests/SessionLogAccumulatorTests.swift`: parser, day-boundary, family, and reset behavior.
- `Tests/CodexMenuBarCoreTests/RateLimitReducerTests.swift`: aggregation, canonical priority, time-zone, reset, and formatter behavior.
- `Tests/CodexMenuBarCoreTests/DashboardReaderTests.swift`: injected calendar/clock integration.
- `Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`: finite SwiftUI layout with Today data.
- `README.md` and `README.zh-CN.md`: user-facing feature description.

---

### Task 1: Build a bounded daily trace in the log accumulator

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/LogIndexModels.swift:44-115`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/SessionLogAccumulator.swift:18-170`
- Test: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/SessionLogAccumulatorTests.swift`

**Interfaces:**
- Consumes: `RateLimitCandidate`, `RawRateLimitWindow`, the `today` and `calendar` arguments already supplied to `SessionLogAccumulator.consume`.
- Produces:
  - `DailyRateLimitWindowObservation`
  - `DailyRateLimitWindowTrace`
  - `DailyRateLimitFamilyTrace`
  - `DailyRateLimitTrace`
  - `SessionLogSummary.dailyRateLimitTrace: DailyRateLimitTrace?`

- [ ] **Step 1: Run the current full suite as a clean baseline**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: all existing tests pass before feature changes.

- [ ] **Step 2: Write the failing test for earliest values and independent reset state**

Extend the test helper so one record can describe both windows and reset
deadlines:

```swift
private func limit(
    primaryUsed: Int?,
    secondaryUsed: Int? = nil,
    primaryReset: Int? = nil,
    secondaryReset: Int? = nil,
    limitID: String = "codex",
    at timestamp: String
) -> String {
    let primary = primaryUsed.map { used -> String in
        var fields = ["\"used_percent\":\(used)", "\"window_minutes\":300"]
        if let primaryReset { fields.append("\"resets_at\":\(primaryReset)") }
        return "\"primary\":{\(fields.joined(separator: ","))}"
    }
    let secondary = secondaryUsed.map { used -> String in
        var fields = ["\"used_percent\":\(used)", "\"window_minutes\":10080"]
        if let secondaryReset { fields.append("\"resets_at\":\(secondaryReset)") }
        return "\"secondary\":{\(fields.joined(separator: ","))}"
    }
    let windows = [primary, secondary].compactMap { $0 }.joined(separator: ",")
    return """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"\(limitID)",\(windows)}}}
    """
}

private func limit(used: Int, at timestamp: String) -> String {
    limit(primaryUsed: used, at: timestamp)
}
```

Add:

```swift
func testDailyRateTraceKeepsEarliestValuesAndIndependentResetState() throws {
    var accumulator = makeAccumulator()
    let cutoff = try date("2026-05-23T00:00:00Z")
    let today = try date("2026-07-21T00:00:00Z")

    consume(
        limit(primaryUsed: 20, secondaryUsed: 40, primaryReset: 100, secondaryReset: 700, at: "2026-07-21T01:00:00Z"),
        line: 1, into: &accumulator, cutoff: cutoff, today: today
    )
    consume(
        limit(primaryUsed: 28, secondaryUsed: 42, primaryReset: 100, secondaryReset: 700, at: "2026-07-21T02:00:00Z"),
        line: 2, into: &accumulator, cutoff: cutoff, today: today
    )
    consume(
        limit(primaryUsed: 8, secondaryUsed: 45, primaryReset: 200, secondaryReset: 700, at: "2026-07-21T06:00:00Z"),
        line: 3, into: &accumulator, cutoff: cutoff, today: today
    )

    let trace = try XCTUnwrap(accumulator.summary(modifiedAt: modifiedAt, threadName: nil).dailyRateLimitTrace)
    XCTAssertEqual(trace.day, today)
    XCTAssertEqual(trace.canonical?.primary?.first.usedPercent, 20)
    XCTAssertEqual(trace.canonical?.secondary?.first.usedPercent, 40)
    XCTAssertEqual(trace.canonical?.primary?.last.usedPercent, 8)
    XCTAssertTrue(trace.canonical?.primary?.didReset ?? false)
    XCTAssertFalse(trace.canonical?.secondary?.didReset ?? true)
}
```

- [ ] **Step 3: Run the new parser test and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter SessionLogAccumulatorTests.testDailyRateTraceKeepsEarliestValuesAndIndependentResetState
```

Expected: compilation fails because `dailyRateLimitTrace` and its trace types do
not exist.

- [ ] **Step 4: Add immutable trace types and the summary property**

Add after `RateLimitCandidate` in `LogIndexModels.swift`:

```swift
public struct DailyRateLimitWindowObservation: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Double?
    public let reportedAt: Date
    public let sequence: Int
    public let sourcePath: String

    public init(
        usedPercent: Double,
        resetsAt: Double?,
        reportedAt: Date,
        sequence: Int,
        sourcePath: String
    ) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.reportedAt = reportedAt
        self.sequence = sequence
        self.sourcePath = sourcePath
    }
}

public struct DailyRateLimitWindowTrace: Equatable, Sendable {
    public let first: DailyRateLimitWindowObservation
    public let last: DailyRateLimitWindowObservation
    public let didReset: Bool

    public init(
        first: DailyRateLimitWindowObservation,
        last: DailyRateLimitWindowObservation,
        didReset: Bool
    ) {
        self.first = first
        self.last = last
        self.didReset = didReset
    }
}

public struct DailyRateLimitFamilyTrace: Equatable, Sendable {
    public let primary: DailyRateLimitWindowTrace?
    public let secondary: DailyRateLimitWindowTrace?

    public init(
        primary: DailyRateLimitWindowTrace?,
        secondary: DailyRateLimitWindowTrace?
    ) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct DailyRateLimitTrace: Equatable, Sendable {
    public let day: Date
    public let canonical: DailyRateLimitFamilyTrace?
    public let fallback: DailyRateLimitFamilyTrace?

    public init(
        day: Date,
        canonical: DailyRateLimitFamilyTrace?,
        fallback: DailyRateLimitFamilyTrace?
    ) {
        self.day = day
        self.canonical = canonical
        self.fallback = fallback
    }
}
```

Add this property and defaulted initializer argument to `SessionLogSummary`:

```swift
public let dailyRateLimitTrace: DailyRateLimitTrace?

// In init:
dailyRateLimitTrace: DailyRateLimitTrace? = nil,

// In the body:
self.dailyRateLimitTrace = dailyRateLimitTrace
```

- [ ] **Step 5: Implement the minimal accumulator builder**

Add private mutable builders near the top of `SessionLogAccumulator.swift`:

```swift
private struct DailyWindowBuilder: Equatable, Sendable {
    var first: DailyRateLimitWindowObservation?
    var last: DailyRateLimitWindowObservation?
    var firstResetAt: Double?
    var didReset = false

    mutating func record(_ observation: DailyRateLimitWindowObservation) {
        if let resetsAt = observation.resetsAt {
            if let firstResetAt, firstResetAt != resetsAt {
                didReset = true
            } else if firstResetAt == nil {
                firstResetAt = resetsAt
            }
        }
        if first.map({ observationOrder(observation, $0) }) ?? true {
            first = observation
        }
        if last.map({ observationOrder($0, observation) }) ?? true {
            last = observation
        }
    }

    func snapshot() -> DailyRateLimitWindowTrace? {
        guard let first, let last else { return nil }
        return DailyRateLimitWindowTrace(first: first, last: last, didReset: didReset)
    }
}

private struct DailyFamilyBuilder: Equatable, Sendable {
    var primary = DailyWindowBuilder()
    var secondary = DailyWindowBuilder()

    var isEmpty: Bool { primary.first == nil && secondary.first == nil }

    func snapshot() -> DailyRateLimitFamilyTrace? {
        guard !isEmpty else { return nil }
        return DailyRateLimitFamilyTrace(
            primary: primary.snapshot(),
            secondary: secondary.snapshot()
        )
    }
}

private func observationOrder(
    _ lhs: DailyRateLimitWindowObservation,
    _ rhs: DailyRateLimitWindowObservation
) -> Bool {
    if lhs.reportedAt != rhs.reportedAt { return lhs.reportedAt < rhs.reportedAt }
    if lhs.sourcePath != rhs.sourcePath { return lhs.sourcePath < rhs.sourcePath }
    return lhs.sequence < rhs.sequence
}
```

Add accumulator state:

```swift
private var dailyRateLimitDay: Date?
private var dailyCanonicalRateLimit = DailyFamilyBuilder()
private var dailyFallbackRateLimit = DailyFamilyBuilder()
```

After constructing each `RateLimitCandidate`, call:

```swift
recordDailyRateLimit(candidate, today: today, calendar: calendar)
```

Add:

```swift
private mutating func recordDailyRateLimit(
    _ candidate: RateLimitCandidate,
    today: Date,
    calendar: Calendar
) {
    guard let reportedAt = candidate.reportedAt,
          calendar.startOfDay(for: reportedAt) == today
    else {
        return
    }
    if dailyRateLimitDay != today {
        dailyRateLimitDay = today
        dailyCanonicalRateLimit = DailyFamilyBuilder()
        dailyFallbackRateLimit = DailyFamilyBuilder()
    }
    let primary = observation(candidate.primary, candidate: candidate, reportedAt: reportedAt)
    let secondary = observation(candidate.secondary, candidate: candidate, reportedAt: reportedAt)
    if candidate.limitID == "codex" {
        if let primary { dailyCanonicalRateLimit.primary.record(primary) }
        if let secondary { dailyCanonicalRateLimit.secondary.record(secondary) }
    } else {
        if let primary { dailyFallbackRateLimit.primary.record(primary) }
        if let secondary { dailyFallbackRateLimit.secondary.record(secondary) }
    }
}

private func observation(
    _ window: RawRateLimitWindow?,
    candidate: RateLimitCandidate,
    reportedAt: Date
) -> DailyRateLimitWindowObservation? {
    guard let usedPercent = window?.usedPercent, usedPercent.isFinite else { return nil }
    return DailyRateLimitWindowObservation(
        usedPercent: usedPercent,
        resetsAt: window?.resetsAt,
        reportedAt: reportedAt,
        sequence: candidate.sequence,
        sourcePath: candidate.sourcePath
    )
}
```

In `prune(cutoff:today:)`, clear stale daily state:

```swift
if dailyRateLimitDay != today {
    dailyRateLimitDay = nil
    dailyCanonicalRateLimit = DailyFamilyBuilder()
    dailyFallbackRateLimit = DailyFamilyBuilder()
}
```

Pass this argument when building `SessionLogSummary`:

```swift
dailyRateLimitTrace: dailyRateLimitDay.map {
    DailyRateLimitTrace(
        day: $0,
        canonical: dailyCanonicalRateLimit.snapshot(),
        fallback: dailyFallbackRateLimit.snapshot()
    )
},
```

- [ ] **Step 6: Run the parser test and verify GREEN**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter SessionLogAccumulatorTests.testDailyRateTraceKeepsEarliestValuesAndIndependentResetState
```

Expected: the selected test passes.

- [ ] **Step 7: Add RED tests for ignored events, day rollover, and family separation**

Add focused tests:

```swift
func testDailyRateTraceIgnoresNonTodayAndTimestampFreeEvents() throws {
    var accumulator = makeAccumulator()
    let cutoff = try date("2026-05-23T00:00:00Z")
    let today = try date("2026-07-21T00:00:00Z")

    consume(limit(primaryUsed: 70, at: "2026-07-20T23:59:59Z"), line: 1, into: &accumulator, cutoff: cutoff, today: today)
    consume(#"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":60,"window_minutes":300}}}}"#, line: 2, into: &accumulator, cutoff: cutoff, today: today)
    consume(#"{"timestamp":"2026-07-21T00:30:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":"bad","window_minutes":300}}}}"#, line: 3, into: &accumulator, cutoff: cutoff, today: today)
    consume(limit(primaryUsed: 20, at: "2026-07-21T01:00:00Z"), line: 4, into: &accumulator, cutoff: cutoff, today: today)
    consume(limit(primaryUsed: 90, at: "2026-07-22T00:00:00Z"), line: 5, into: &accumulator, cutoff: cutoff, today: today)

    let trace = try XCTUnwrap(accumulator.summary(modifiedAt: modifiedAt, threadName: nil).dailyRateLimitTrace)
    XCTAssertEqual(trace.canonical?.primary?.first.usedPercent, 20)
}

func testPruneDropsYesterdayTraceAndCanonicalDoesNotOverwriteFallback() throws {
    var accumulator = makeAccumulator()
    let cutoff = try date("2026-05-23T00:00:00Z")
    let july21 = try date("2026-07-21T00:00:00Z")
    let july22 = try date("2026-07-22T00:00:00Z")

    consume(limit(primaryUsed: 60, limitID: "codex_spark", at: "2026-07-21T01:00:00Z"), line: 1, into: &accumulator, cutoff: cutoff, today: july21)
    consume(limit(primaryUsed: 20, at: "2026-07-21T02:00:00Z"), line: 2, into: &accumulator, cutoff: cutoff, today: july21)

    var trace = try XCTUnwrap(accumulator.summary(modifiedAt: modifiedAt, threadName: nil).dailyRateLimitTrace)
    XCTAssertEqual(trace.canonical?.primary?.first.usedPercent, 20)
    XCTAssertEqual(trace.fallback?.primary?.first.usedPercent, 60)

    accumulator.prune(cutoff: cutoff, today: july22)
    trace = accumulator.summary(modifiedAt: modifiedAt, threadName: nil).dailyRateLimitTrace
    XCTAssertNil(trace)
}

func testMissingResetMetadataDoesNotInferReset() throws {
    var accumulator = makeAccumulator()
    let cutoff = try date("2026-05-23T00:00:00Z")
    let today = try date("2026-07-21T00:00:00Z")

    consume(limit(primaryUsed: 20, at: "2026-07-21T01:00:00Z"), line: 1, into: &accumulator, cutoff: cutoff, today: today)
    consume(limit(primaryUsed: 8, at: "2026-07-21T06:00:00Z"), line: 2, into: &accumulator, cutoff: cutoff, today: today)

    let trace = try XCTUnwrap(accumulator.summary(modifiedAt: modifiedAt, threadName: nil).dailyRateLimitTrace)
    XCTAssertFalse(trace.canonical?.primary?.didReset ?? true)
}
```

- [ ] **Step 8: Run all accumulator tests and complete GREEN**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter SessionLogAccumulatorTests
```

Expected: all accumulator tests pass.

- [ ] **Step 9: Commit the parser deliverable**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/LogIndexModels.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/SessionLogAccumulator.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/SessionLogAccumulatorTests.swift
git commit -m "feat: index daily usage baselines"
```

---

### Task 2: Reduce daily traces into Usage card state

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitModels.swift:3-108`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitReducer.swift:3-53`
- Test: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/RateLimitReducerTests.swift`

**Interfaces:**
- Consumes: `SessionLogSummary.dailyRateLimitTrace`, injected `Calendar`, injected `Date`.
- Produces:
  - `WindowUsage.todayInitialRemainingPercent: Int?`
  - `WindowUsage.didResetToday: Bool`
  - `UsageFormatting.todayInitialLabel(_:) -> String?`
  - `RateLimitReducer.reduce(summaries:calendar:now:)`

- [ ] **Step 1: Write RED reducer tests for initial values, family priority, and reset merging**

Add a helper that constructs immutable traces:

```swift
private func dailyTrace(
    day: Date,
    canonicalPrimary: (used: Double, reset: Double?, at: Date)? = nil,
    canonicalSecondary: (used: Double, reset: Double?, at: Date)? = nil,
    fallbackPrimary: (used: Double, reset: Double?, at: Date)? = nil,
    primaryDidReset: Bool = false
) -> DailyRateLimitTrace {
    func window(
        _ value: (used: Double, reset: Double?, at: Date)?,
        didReset: Bool
    ) -> DailyRateLimitWindowTrace? {
        guard let value else { return nil }
        let observation = DailyRateLimitWindowObservation(
            usedPercent: value.used,
            resetsAt: value.reset,
            reportedAt: value.at,
            sequence: 1,
            sourcePath: "/trace.jsonl"
        )
        return DailyRateLimitWindowTrace(first: observation, last: observation, didReset: didReset)
    }
    return DailyRateLimitTrace(
        day: day,
        canonical: DailyRateLimitFamilyTrace(
            primary: window(canonicalPrimary, didReset: primaryDidReset),
            secondary: window(canonicalSecondary, didReset: false)
        ),
        fallback: DailyRateLimitFamilyTrace(
            primary: window(fallbackPrimary, didReset: false),
            secondary: nil
        )
    )
}
```

Extend the `log` helper with `dailyTrace: DailyRateLimitTrace? = nil` and pass
it to `SessionLogSummary`.

Add:

```swift
func testBuildsTodayInitialStateFromEarliestSameFamilyTrace() throws {
    let calendar = utcCalendar()
    let now = date("2026-07-21T12:00:00Z")
    let day = calendar.startOfDay(for: now)
    let current = candidate(limitID: "codex", usedPrimary: 28, usedSecondary: 40, reportedAt: now)

    let snapshot = try snapshot(from: RateLimitReducer().reduce(
        summaries: [
            log(
                path: "/later.jsonl",
                candidates: [current],
                dailyTrace: dailyTrace(
                    day: day,
                    canonicalPrimary: (used: 25, reset: 200, at: date("2026-07-21T02:00:00Z")),
                    canonicalSecondary: (used: 40, reset: 700, at: date("2026-07-21T02:00:00Z"))
                )
            ),
            log(
                path: "/earlier.jsonl",
                candidates: [],
                dailyTrace: dailyTrace(
                    day: day,
                    canonicalPrimary: (used: 20, reset: 100, at: date("2026-07-21T01:00:00Z")),
                    fallbackPrimary: (used: 5, reset: 50, at: date("2026-07-21T00:30:00Z"))
                )
            )
        ],
        calendar: calendar,
        now: now
    ))

    XCTAssertEqual(snapshot.primary?.remainingPercent, 72)
    XCTAssertEqual(snapshot.primary?.todayInitialRemainingPercent, 80)
    XCTAssertTrue(snapshot.primary?.didResetToday ?? false)
    XCTAssertEqual(snapshot.secondary?.todayInitialRemainingPercent, 60)
    XCTAssertFalse(snapshot.secondary?.didResetToday ?? true)
}
```

- [ ] **Step 2: Run the reducer test and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter RateLimitReducerTests.testBuildsTodayInitialStateFromEarliestSameFamilyTrace
```

Expected: compilation fails because the new `WindowUsage` fields and reducer
arguments do not exist.

- [ ] **Step 3: Add Today fields and exact formatter**

Extend `WindowUsage`:

```swift
public let todayInitialRemainingPercent: Int?
public let didResetToday: Bool

public init(
    label: String,
    usedPercent: Double?,
    remainingPercent: Int?,
    resetsAt: Date?,
    todayInitialRemainingPercent: Int? = nil,
    didResetToday: Bool = false
) {
    self.label = label
    self.usedPercent = usedPercent
    self.remainingPercent = remainingPercent
    self.resetsAt = resetsAt
    self.todayInitialRemainingPercent = todayInitialRemainingPercent
    self.didResetToday = didResetToday
}
```

Add to `UsageFormatting`:

```swift
public static func todayInitialLabel(_ window: WindowUsage?) -> String? {
    guard let initial = window?.todayInitialRemainingPercent else { return nil }
    return "Today initial: \(initial)%"
        + (window?.didResetToday == true ? " · reset today" : "")
}
```

- [ ] **Step 4: Implement same-family daily reduction**

Replace the current public-to-private candidate-only reducer flow with one
public method. Keep the existing newest-candidate loop and missing-event error,
then add daily family selection before constructing `UsageSnapshot`:

```swift
public func reduce(
    summaries: [SessionLogSummary],
    calendar: Calendar = .current,
    now: Date = Date()
) -> UsageReadResult {
    var newest: RateLimitCandidate?
    for candidate in summaries.compactMap(\.latestRateLimit)
    where candidate.primary != nil || candidate.secondary != nil {
        if RateLimitCandidateOrdering.isNewer(candidate, than: newest) {
            newest = candidate
        }
    }
    guard let newest else {
        return .failure(UsageReadError(
            menuValue: "--",
            message: "No rate limit event found yet. Open or use Codex once to generate usage data.",
            detail: nil
        ))
    }

    let today = calendar.startOfDay(for: now)
    let useCanonical = newest.limitID == "codex"
    let families = summaries.compactMap { summary -> DailyRateLimitFamilyTrace? in
        guard let trace = summary.dailyRateLimitTrace, trace.day == today else { return nil }
        return useCanonical ? trace.canonical : trace.fallback
    }

    return .snapshot(UsageSnapshot(
        primary: makeWindow(newest.primary, traces: families.compactMap(\.primary)),
        secondary: makeWindow(newest.secondary, traces: families.compactMap(\.secondary)),
        planType: newest.planType,
        creditsDescription: creditsDescription(newest.credits),
        reportedAt: newest.reportedAt,
        sourcePath: newest.sourcePath
    ))
}
```

Replace `makeWindow` with:

```swift
private func makeWindow(
    _ raw: RawRateLimitWindow?,
    traces: [DailyRateLimitWindowTrace]
) -> WindowUsage? {
    guard let raw else { return nil }
    let first = traces.map(\.first).min(by: observationOrder)
    let resetMarkers = Set(
        traces.flatMap { [$0.first, $0.last] }.compactMap(\.resetsAt)
    )
    return WindowUsage(
        label: UsageFormatting.windowLabel(minutes: raw.windowMinutes),
        usedPercent: raw.usedPercent,
        remainingPercent: UsageFormatting.remainingFromUsed(raw.usedPercent),
        resetsAt: raw.resetsAt.map(Date.init(timeIntervalSince1970:)),
        todayInitialRemainingPercent: UsageFormatting.remainingFromUsed(first?.usedPercent),
        didResetToday: traces.contains(where: \.didReset) || resetMarkers.count > 1
    )
}

private func observationOrder(
    _ lhs: DailyRateLimitWindowObservation,
    _ rhs: DailyRateLimitWindowObservation
) -> Bool {
    if lhs.reportedAt != rhs.reportedAt { return lhs.reportedAt < rhs.reportedAt }
    if lhs.sourcePath != rhs.sourcePath { return lhs.sourcePath < rhs.sourcePath }
    return lhs.sequence < rhs.sequence
}
```

- [ ] **Step 5: Run the reducer test and verify GREEN**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter RateLimitReducerTests.testBuildsTodayInitialStateFromEarliestSameFamilyTrace
```

Expected: selected test passes.

- [ ] **Step 6: Add RED tests for omission, local-day selection, and exact copy**

Add:

```swift
func testTodayInitialIgnoresTraceFromDifferentLocalDay() throws {
    var pacific = Calendar(identifier: .gregorian)
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = date("2026-07-21T06:30:00Z")
    let utcDay = utcCalendar().startOfDay(for: now)
    let current = candidate(limitID: "codex", usedPrimary: 28, reportedAt: now)

    let snapshot = try snapshot(from: RateLimitReducer().reduce(
        summaries: [log(
            path: "/utc.jsonl",
            candidates: [current],
            dailyTrace: dailyTrace(
                day: utcDay,
                canonicalPrimary: (used: 20, reset: 100, at: now)
            )
        )],
        calendar: pacific,
        now: now
    ))

    XCTAssertNil(snapshot.primary?.todayInitialRemainingPercent)
    XCTAssertFalse(snapshot.primary?.didResetToday ?? true)
}

func testTodayInitialFormattingIsExactAndOmitsMissingState() {
    XCTAssertNil(UsageFormatting.todayInitialLabel(nil))
    XCTAssertNil(UsageFormatting.todayInitialLabel(
        WindowUsage(label: "5h", usedPercent: 20, remainingPercent: 80, resetsAt: nil)
    ))
    XCTAssertEqual(
        UsageFormatting.todayInitialLabel(WindowUsage(
            label: "5h",
            usedPercent: 20,
            remainingPercent: 80,
            resetsAt: nil,
            todayInitialRemainingPercent: 50,
            didResetToday: false
        )),
        "Today initial: 50%"
    )
    XCTAssertEqual(
        UsageFormatting.todayInitialLabel(WindowUsage(
            label: "5h",
            usedPercent: 8,
            remainingPercent: 92,
            resetsAt: nil,
            todayInitialRemainingPercent: 50,
            didResetToday: true
        )),
        "Today initial: 50% · reset today"
    )
}

func testFallbackCurrentUsesFallbackDailyTrace() throws {
    let calendar = utcCalendar()
    let now = date("2026-07-21T12:00:00Z")
    let day = calendar.startOfDay(for: now)
    let current = candidate(limitID: "codex_spark", usedPrimary: 30, reportedAt: now)

    let snapshot = try snapshot(from: RateLimitReducer().reduce(
        summaries: [log(
            path: "/fallback.jsonl",
            candidates: [current],
            dailyTrace: dailyTrace(
                day: day,
                canonicalPrimary: (used: 90, reset: 900, at: date("2026-07-21T00:30:00Z")),
                fallbackPrimary: (used: 20, reset: 100, at: date("2026-07-21T01:00:00Z"))
            )
        )],
        calendar: calendar,
        now: now
    ))

    XCTAssertEqual(snapshot.primary?.todayInitialRemainingPercent, 80)
}
```

- [ ] **Step 7: Run all reducer tests and complete GREEN**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter RateLimitReducerTests
```

Expected: all reducer tests pass, including the existing priority and current
Usage tests.

- [ ] **Step 8: Commit the reducer deliverable**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitModels.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/RateLimitReducer.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/RateLimitReducerTests.swift
git commit -m "feat: calculate today initial usage"
```

---

### Task 3: Inject the dashboard clock and render the Usage-card line

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/DashboardReader.swift:80-94`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/Components.swift:42-67`
- Test: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/DashboardReaderTests.swift`
- Test: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`

**Interfaces:**
- Consumes: `RateLimitReducer.reduce(summaries:calendar:now:)` and `UsageFormatting.todayInitialLabel`.
- Produces: a conditional caption line in both existing `UsageCard` instances.

- [ ] **Step 1: Write the RED dashboard integration test**

Extend the `DashboardReaderTests.summary` helper to attach a canonical daily
trace for the injected `now`. Add:

```swift
func testUsageReductionUsesInjectedCalendarAndClock() {
    let reader = makeReader(
        indexResults: [.success(snapshot(summaries: [
            summary(hasRateLimit: true, totalTokens: 0, initialUsedPercent: 40)
        ]))],
        processes: .success([])
    )

    let output = reader.read()

    guard case let .content(usage) = output.rateLimit else {
        return XCTFail("Expected usage content")
    }
    XCTAssertEqual(usage.primary?.remainingPercent, 75)
    XCTAssertEqual(usage.primary?.todayInitialRemainingPercent, 60)
}
```

Add `initialUsedPercent: Double? = nil` to the helper. Before returning
`SessionLogSummary`, construct:

```swift
let dailyTrace = initialUsedPercent.map { initialUsed -> DailyRateLimitTrace in
    let observation = DailyRateLimitWindowObservation(
        usedPercent: initialUsed,
        resetsAt: nil,
        reportedAt: now,
        sequence: 0,
        sourcePath: path
    )
    return DailyRateLimitTrace(
        day: utcCalendar().startOfDay(for: now),
        canonical: DailyRateLimitFamilyTrace(
            primary: DailyRateLimitWindowTrace(
                first: observation,
                last: observation,
                didReset: false
            ),
            secondary: nil
        ),
        fallback: nil
    )
}
```

Pass `dailyRateLimitTrace: dailyTrace` to `SessionLogSummary`.

- [ ] **Step 2: Run the integration test and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardReaderTests.testUsageReductionUsesInjectedCalendarAndClock
```

Expected: assertion fails with a nil Today initial value because
`DashboardReader` still calls the reducer without its injected calendar/clock.

- [ ] **Step 3: Pass the injected calendar and clock**

Change the reducer call in `DashboardReader.read()` to:

```swift
switch rateLimitReducer.reduce(
    summaries: indexSnapshot.summaries,
    calendar: calendar,
    now: readAt
) {
```

- [ ] **Step 4: Run the integration test and verify GREEN**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardReaderTests.testUsageReductionUsesInjectedCalendarAndClock
```

Expected: selected test passes.

- [ ] **Step 5: Write the RED test for the Usage-card Today text**

Add to `DashboardViewSmokeTests`:

```swift
func testUsageCardExposesTodayInitialTextFromWindowState() {
    let card = UsageCard(
        title: "Primary",
        window: WindowUsage(
            label: "5h",
            usedPercent: 8,
            remainingPercent: 92,
            resetsAt: nil,
            todayInitialRemainingPercent: 50,
            didResetToday: true
        )
    )

    XCTAssertEqual(card.todayInitialText, "Today initial: 50% · reset today")
}
```

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardViewSmokeTests.testUsageCardExposesTodayInitialTextFromWindowState
```

Expected: compilation fails because `UsageCard.todayInitialText` does not
exist.

- [ ] **Step 6: Expose and render the optional Today line**

Add to `UsageCard`:

```swift
var todayInitialText: String? {
    UsageFormatting.todayInitialLabel(window)
}
```

Insert between `ProgressView` and the reset deadline:

```swift
if let todayInitialText {
    Text(todayInitialText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
}
```

Update `DashboardViewSmokeTests.usage()` to keep both normal and reset data in
the full layout fixture:

```swift
primary: WindowUsage(
    label: "5h",
    usedPercent: 28,
    remainingPercent: 72,
    resetsAt: nil,
    todayInitialRemainingPercent: 80,
    didResetToday: false
),
secondary: WindowUsage(
    label: "7d",
    usedPercent: 40,
    remainingPercent: 60,
    resetsAt: nil,
    todayInitialRemainingPercent: 70,
    didResetToday: true
),
```

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter DashboardViewSmokeTests.testUsageCardExposesTodayInitialTextFromWindowState
```

Expected: selected test passes.

- [ ] **Step 7: Run UI, reader, and routing smoke suites**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar --filter 'DashboardReaderTests|DashboardViewSmokeTests|DashboardRoutingTests'
```

Expected: all selected tests pass with finite layout.

- [ ] **Step 8: Commit the UI integration deliverable**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBarCore/DashboardReader.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/Components.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarCoreTests/DashboardReaderTests.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift
git commit -m "feat: show today initial usage"
```

---

### Task 4: Document and fully verify the feature

**Files:**
- Modify: `README.md:28-33`
- Modify: `README.zh-CN.md:28-33`

**Interfaces:**
- Consumes: completed Today initial behavior.
- Produces: bilingual user-facing documentation and fresh full-suite evidence.

- [ ] **Step 1: Update the English feature summary**

Change the Overview bullet to:

```markdown
- **Overview** — see current rate-limit windows and each window's initial remaining percentage for today, a compact Token heatmap, and shortcuts to live sessions.
```

- [ ] **Step 2: Update the Simplified Chinese feature summary**

Change the corresponding bullet to:

```markdown
- **概览** — 查看当前速率限制周期及各周期今日初始剩余百分比、紧凑的 Token 热力图，以及实时会话快捷入口。
```

- [ ] **Step 3: Run the complete verification matrix**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
bash -n codex-menubar/macos/CodexMenuBar/scripts/build-app.sh codex-menubar/macos/CodexMenuBar/scripts/package-release.sh
git diff --check
```

Expected:

- all Swift tests pass with zero failures;
- both shell scripts pass syntax validation;
- `git diff --check` produces no output.

- [ ] **Step 4: Review the requirement checklist against the diff**

Run:

```bash
git status --short
git diff --stat main...HEAD
git diff main -- codex-menubar/macos/CodexMenuBar/Sources codex-menubar/macos/CodexMenuBar/Tests README.md README.zh-CN.md
```

Confirm from the output:

- only the approved Usage-card feature, tests, spec/plan, and README copy changed;
- no Session Token percentage was added;
- no persistence or unbounded event array was added;
- exact Today strings match the spec.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: describe today initial usage"
```

- [ ] **Step 6: Hand off through the repository PR workflow**

Push `feature/today-initial-usage`, open a PR to `main`, and include exact test
counts and commands in the PR body. Do not merge until the PR is reviewed.
