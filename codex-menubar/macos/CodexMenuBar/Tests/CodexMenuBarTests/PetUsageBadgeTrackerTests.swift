import CoreGraphics
import XCTest
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgeTrackerTests: XCTestCase {
    func testAbsentCodexUsesFiveSecondProcessDiscoveryWithoutLocatorScan() async {
        let timing = ManualTrackerTiming(maxSleeps: 1)
        let locator = SequencedPetWindowLocator()
        let tracker = makeTracker(
            locator: locator,
            timing: timing,
            codexIsRunning: false
        )

        tracker.start()
        await waitForSleeps(1, timing: timing)
        tracker.stop()

        let durations = await timing.recordedDurations()
        let counts = await locator.callCounts()
        XCTAssertEqual(durations, [.seconds(5)])
        XCTAssertEqual(counts, .init(discover: 0, refresh: 0))
    }

    func testUndiscoveredPetRetriesAfterTwoSeconds() async {
        let timing = ManualTrackerTiming(maxSleeps: 1)
        let locator = SequencedPetWindowLocator(discoveries: [nil])
        let tracker = makeTracker(locator: locator, timing: timing)

        tracker.start()
        await waitForSleeps(1, timing: timing)
        tracker.stop()

        let durations = await timing.recordedDurations()
        XCTAssertEqual(durations, [.seconds(2)])
    }

    func testStablePetUsesFiveHundredMillisecondTargetedRefresh() async {
        let timing = ManualTrackerTiming(maxSleeps: 2)
        let original = observation()
        let locator = SequencedPetWindowLocator(
            discoveries: [original],
            refreshes: [original]
        )
        let tracker = makeTracker(locator: locator, timing: timing)

        tracker.start()
        await waitForSleeps(2, timing: timing)
        tracker.stop()

        let durations = await timing.recordedDurations()
        XCTAssertEqual(durations, [.milliseconds(500), .milliseconds(500)])
    }

    func testMovementUsesSeventyFiveMillisecondsThenReturnsToStableCadence() async {
        let timing = ManualTrackerTiming(maxSleeps: 12)
        let original = observation()
        let moved = observation(x: 920)
        let locator = SequencedPetWindowLocator(
            discoveries: [original],
            refreshes: [moved] + Array(repeating: moved, count: 12)
        )
        var updates: [PetUsageBadgeTrackingUpdate] = []
        let tracker = makeTracker(locator: locator, timing: timing)
        tracker.onUpdate = { updates.append($0) }

        tracker.start()
        await waitForSleeps(12, timing: timing)
        tracker.stop()

        let durations = await timing.recordedDurations()
        XCTAssertEqual(durations.first, .milliseconds(500))
        XCTAssertEqual(
            Array(durations.dropFirst().prefix(10)),
            Array(repeating: .milliseconds(75), count: 10)
        )
        XCTAssertEqual(durations.last, .milliseconds(500))
        XCTAssertTrue(updates.contains(where: \.isMoving))
    }

    func testFullDiscoveryRunsEveryTenSeconds() async {
        let timing = ManualTrackerTiming(maxSleeps: 21)
        let original = observation()
        let locator = SequencedPetWindowLocator(
            discoveries: [original, original],
            refreshes: Array(repeating: original, count: 24)
        )
        let tracker = makeTracker(locator: locator, timing: timing)

        tracker.start()
        await waitForSleeps(21, timing: timing)
        tracker.stop()

        let counts = await locator.callCounts()
        XCTAssertEqual(counts.discover, 2)
    }

    func testTrackedFailureBacksOffOneTwoThenFiveSeconds() async {
        let timing = ManualTrackerTiming(maxSleeps: 4)
        let original = observation()
        let locator = SequencedPetWindowLocator(
            discoveries: [original, nil, nil],
            refreshes: [nil]
        )
        var updates: [PetUsageBadgeTrackingUpdate] = []
        let tracker = makeTracker(locator: locator, timing: timing)
        tracker.onUpdate = { updates.append($0) }

        tracker.start()
        await waitForSleeps(4, timing: timing)
        tracker.stop()

        let durations = await timing.recordedDurations()
        XCTAssertEqual(
            durations,
            [.milliseconds(500), .seconds(1), .seconds(2), .seconds(5)]
        )
        XCTAssertTrue(updates.contains { $0.observation == nil })
    }

    func testSingleLoopNeverOverlapsLocatorCalls() async {
        let timing = ManualTrackerTiming(maxSleeps: 8)
        let original = observation()
        let locator = SequencedPetWindowLocator(
            discoveries: [original],
            refreshes: Array(repeating: original, count: 10)
        )
        let tracker = makeTracker(locator: locator, timing: timing)

        tracker.start()
        await waitForSleeps(8, timing: timing)
        tracker.stop()

        let maximumActiveCalls = await locator.maximumActiveCallCount()
        XCTAssertEqual(maximumActiveCalls, 1)
    }

    private func makeTracker(
        locator: SequencedPetWindowLocator,
        timing: ManualTrackerTiming,
        codexIsRunning: Bool = true
    ) -> PetUsageBadgeTracker {
        PetUsageBadgeTracker(
            locator: locator,
            codexIsRunning: { codexIsRunning },
            timing: timing
        )
    }

    private func waitForSleeps(
        _ expected: Int,
        timing: ManualTrackerTiming
    ) async {
        for _ in 0 ..< 1_000 {
            if await timing.sleepCount() >= expected { return }
            await Task.yield()
        }
        XCTFail("Tracker did not schedule \(expected) sleeps")
    }

    private func observation(x: CGFloat = 900) -> PetWindowObservation {
        PetWindowObservation(
            anchorWindowID: 10,
            trackedWindowIDs: [10, 11],
            anchorFrame: CGRect(x: x, y: 500, width: 243, height: 253),
            obstacleFrames: [],
            processIdentifier: 42,
            appVersion: "26.721.41059"
        )
    }
}

private actor ManualTrackerTiming: PetUsageTrackerTiming {
    enum Stop: Error {
        case requested
    }

    private let maxSleeps: Int
    private var now: UInt64 = 0
    private var durations: [Duration] = []

    init(maxSleeps: Int) {
        self.maxSleeps = maxSleeps
    }

    func nowNanoseconds() -> UInt64 {
        now
    }

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        now += duration.nanoseconds
        if durations.count >= maxSleeps {
            throw Stop.requested
        }
        await Task.yield()
    }

    func sleepCount() -> Int {
        durations.count
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

private actor SequencedPetWindowLocator: PetWindowLocating {
    struct CallCounts: Equatable {
        let discover: Int
        let refresh: Int
    }

    private var discoveries: [PetWindowObservation?]
    private var refreshes: [PetWindowObservation?]
    private var discoveryCount = 0
    private var refreshCount = 0
    private var activeCallCount = 0
    private var maximumActiveCalls = 0

    init(
        discoveries: [PetWindowObservation?] = [],
        refreshes: [PetWindowObservation?] = []
    ) {
        self.discoveries = discoveries
        self.refreshes = refreshes
    }

    func discover() async -> PetWindowObservation? {
        discoveryCount += 1
        await beginCall()
        defer { endCall() }
        return discoveries.isEmpty ? nil : discoveries.removeFirst()
    }

    func refresh(
        _ previous: PetWindowObservation
    ) async -> PetWindowObservation? {
        refreshCount += 1
        await beginCall()
        defer { endCall() }
        return refreshes.isEmpty ? previous : refreshes.removeFirst()
    }

    func callCounts() -> CallCounts {
        CallCounts(discover: discoveryCount, refresh: refreshCount)
    }

    func maximumActiveCallCount() -> Int {
        maximumActiveCalls
    }

    private func beginCall() async {
        activeCallCount += 1
        maximumActiveCalls = max(maximumActiveCalls, activeCallCount)
        await Task.yield()
    }

    private func endCall() {
        activeCallCount -= 1
    }
}

private extension Duration {
    var nanoseconds: UInt64 {
        let components = self.components
        let seconds = UInt64(max(0, components.seconds))
        let attoseconds = UInt64(max(0, components.attoseconds))
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
