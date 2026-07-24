# Today Initial Usage Design

## Goal

Show the first remaining Usage percentage observed during the current local
calendar day in each Usage card. This gives the user a stable daily reference
without repeating the card's current remaining percentage or presenting an
unreliable Token-to-quota conversion.

## User Experience

The existing large percentage, progress bar, and reset deadline remain
unchanged. A compact line appears between the progress bar and reset deadline.

When the window has not reset today:

```text
Today initial: 80%
```

When the window has reset today:

```text
Today initial: 50% · reset today
```

Primary and Secondary calculate and render this state independently.

The line is omitted when no valid, timestamped Usage event exists for the
current local day. The card otherwise remains fully usable.

## Definitions

- **Today** is the local calendar day from the `Calendar` injected into the
  dashboard read.
- **Initial** is the earliest valid remaining percentage observed in a
  timestamped Usage event on that day. It is not claimed to be a midnight
  snapshot.
- **Remaining percentage** is `100 - used_percent`, clamped and rounded with
  the existing `UsageFormatting.remainingFromUsed` rule.
- **Reset today** means the log contains two valid observations for the same
  window during the day whose `resets_at` values differ. No reset is inferred
  when reset metadata is absent.

## Scope

### In scope

- Daily initial remaining percentage for Primary and Secondary.
- Independent reset detection for both windows.
- Recovery from local JSONL logs after an app restart.
- Local-calendar and midnight correctness.
- Bounded in-memory summaries.
- Unit and SwiftUI smoke coverage.

### Out of scope

- Calculating quota percentage from Session Token counts.
- Showing current percentage a second time in the Today line.
- Showing percentage points consumed today.
- Persisting a baseline in `UserDefaults` or another app-owned store.
- Retaining every raw Usage event.
- Changing the status-bar icon or History and Sessions screens.

## Architecture

### Parser summary

`SessionLogAccumulator` will continue to parse `token_count.rate_limits`
records. In addition to `latestRateLimit`, it will maintain one bounded
`DailyRateLimitTrace` tagged with the local `today` value injected during the
index refresh. Only valid events whose local day equals that value update the
trace.

The trace stores only mergeable summary information:

- the day;
- the earliest valid Primary observation;
- the earliest valid Secondary observation;
- enough reset metadata to know whether a later observation for each window
  has a different `resets_at` value;
- separate canonical (`limit_id == "codex"`) and fallback limit families so
  the existing selection priority is preserved.

It does not retain every event. When an incremental refresh starts using a new
local day, the next valid event from that day starts a new trace. Older and
future events are ignored for the daily trace. A trace from yesterday is
harmless if a log does not receive new bytes: the reducer selects only a trace
whose day equals today.

`SessionLogSummary` exposes the bounded daily trace alongside the existing
latest candidate.

### Reduction

`RateLimitReducer` receives the injected `Calendar` and read time. It retains
the existing current Usage selection behavior:

1. canonical `codex` candidates win over other limit IDs;
2. the newest candidate within the selected family supplies the current card.

For today's state, the reducer selects traces from the same canonical or
fallback family as the current Usage result. It orders their mergeable edge
observations by event timestamp and then:

1. chooses the earliest valid observation for Primary;
2. chooses the earliest valid observation for Secondary;
3. marks a window reset only if two non-nil `resets_at` values observed in
   timestamp order differ, whether those observations came from the same log
   or different logs;
4. converts each earliest `used_percent` to a remaining percentage with the
   existing formatter.

This prevents a fallback limit from supplying the baseline when a canonical
limit supplies the current card.

### View model and UI

`WindowUsage` gains:

- `todayInitialRemainingPercent: Int?`
- `didResetToday: Bool`

`UsageCard` renders a Today line only when the initial percentage exists:

```text
Today initial: <value>%
```

It appends ` · reset today` when `didResetToday` is true. No second current
value or derived daily-consumption value is displayed.

## Data Flow

1. The incremental index streams new JSONL bytes through
   `SessionLogAccumulator`.
2. Each timestamped rate-limit record updates the log's bounded daily trace
   and its existing latest candidate.
3. `DashboardReader` passes its injected local calendar and `readAt` time to
   `RateLimitReducer`.
4. The reducer combines the latest candidates and today's traces into
   `UsageSnapshot`.
5. `OverviewView` passes each enriched `WindowUsage` to `UsageCard`.
6. The card renders the existing current state and the optional Today line.

No app-owned persistence or network access is added.

## Edge Cases

- A missing or invalid `used_percent` does not establish an initial value for
  that window.
- A missing event timestamp does not participate in the daily trace.
- Yesterday's and future events do not establish today's initial value.
- A Primary observation does not establish a Secondary initial value, or vice
  versa.
- A single valid event produces an initial value and no reset marker.
- Different valid `resets_at` values mark a reset only for the affected window.
- Missing `resets_at` values never cause reset inference.
- A local midnight or time-zone boundary uses the injected calendar rather
  than UTC day arithmetic.
- Existing current Usage behavior remains available even when the Today line
  is omitted.

## Testing Strategy

Implementation follows strict RED-GREEN-REFACTOR cycles.

### Parser tests

- The earliest valid observation on the local day wins.
- Yesterday, future, timestamp-free, and malformed observations are ignored.
- Primary and Secondary retain independent initial observations.
- Reset evidence is tracked independently for both windows.
- Missing reset metadata does not create reset evidence.
- A newer local day replaces the previous daily trace.
- Canonical and fallback families remain distinct.

### Reducer tests

- Current Usage selection remains unchanged.
- The earliest same-family trace supplies today's initial percentage.
- Canonical current Usage cannot consume a fallback baseline.
- Primary and Secondary can have different initial percentages and reset
  states.
- No matching trace leaves Today fields empty.
- Injected time zones and local-midnight boundaries select the correct day.

### Formatting and view tests

- The normal label is exactly `Today initial: 50%`.
- The reset label is exactly
  `Today initial: 50% · reset today`.
- Missing initial data produces no label.
- SwiftUI smoke coverage confirms finite layout with the additional line.

### Full verification

- Run the complete Swift package test suite.
- Run script syntax and diff whitespace checks when preparing delivery.

## Acceptance Criteria

- Both Usage cards can display the day's first remaining percentage.
- The current large remaining percentage remains unchanged.
- Reset text appears only with observed reset evidence.
- The feature survives app restarts by rebuilding from local logs.
- No full event history or new app-owned persistence is introduced.
- Existing rate-limit priority and current Usage behavior do not regress.
- All targeted and full tests pass.
