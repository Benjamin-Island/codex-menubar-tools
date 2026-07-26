import Foundation
import XCTest
@testable import CodexMenuBarCore

final class IncrementalCodexLogIndexTests: XCTestCase {
    private var root: URL!
    private var sessions: URL!
    private let now = Date(timeIntervalSince1970: 1_774_300_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalCodexLogIndexTests-\(UUID().uuidString)", isDirectory: true)
        sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testAppendReadsOnlyNewByteRangeAndUnchangedFileReadsNothing() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)

        _ = try refresh(index)
        let readsAfterFirst = reader.ranges.count
        _ = try refresh(index)
        XCTAssertEqual(reader.ranges.count, readsAfterFirst)

        let oldSize = fixture.byteSize
        try fixture.append(token(total: 160))
        let snapshot = try refresh(index)

        XCTAssertEqual(reader.ranges.last, oldSize..<fixture.byteSize)
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 160)
    }

    func testIncompleteRecordIsAppliedOnlyAfterNewlineCompletesIt() throws {
        let fixture = try LogFixture(
            url: logURL(),
            rawData: Data((metadata() + "\n" + token(total: 100).dropLast(2)).utf8)
        )
        let index = makeIndex(reader: RecordingRangeReader())

        var snapshot = try refresh(index)
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts, .zero)

        try fixture.appendRaw(Data("}}\n".utf8))
        snapshot = try refresh(index)
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 100)
    }

    func testTruncationRebuildsFromZeroAndDropsOldTotals() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        _ = try refresh(index)

        try fixture.replace(records: [metadata(id: "new"), token(total: 7)], atomically: false)
        let snapshot = try refresh(index)

        XCTAssertEqual(reader.ranges.last?.lowerBound, 0)
        XCTAssertEqual(snapshot.summaries.first?.session.id, "new")
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 7)
    }

    func testAtomicReplacementChangesIdentityAndRebuildsFromZero() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        _ = try refresh(index)

        try fixture.replace(records: [metadata(id: "replacement"), token(total: 30)], atomically: true)
        let snapshot = try refresh(index)

        XCTAssertEqual(reader.ranges.last?.lowerBound, 0)
        XCTAssertEqual(snapshot.summaries.first?.session.id, "replacement")
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 30)
    }

    func testBoundaryMutationPlusGrowthForcesByteZeroRebuild() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        _ = try refresh(index)
        let oldSize = fixture.byteSize

        try fixture.overwriteByte(at: oldSize - 2, with: UInt8(ascii: " "))
        try fixture.append(token(total: 160))
        _ = try refresh(index)

        XCTAssertEqual(reader.ranges.last?.lowerBound, 0)
    }

    func testReadFailureKeepsPreviousSuccessfulSummaryAndAddsWarning() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        _ = try refresh(index)
        let oldSize = fixture.byteSize
        try fixture.append(token(total: 160))
        reader.failingLowerBound = oldSize

        let snapshot = try refresh(index)

        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 100)
        XCTAssertEqual(snapshot.warnings.filter { $0.line == 0 }.count, 1)
    }

    func testDeletionRemovesSummaryAndCursor() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        _ = try refresh(index)

        try FileManager.default.removeItem(at: fixture.url)
        let snapshot = try refresh(index)

        XCTAssertTrue(snapshot.summaries.isEmpty)
        XCTAssertEqual(index.cursorCount, 0)
    }

    func testCalendarTimeZoneChangeRebuildsAndChangesDayBucket() throws {
        _ = try LogFixture(
            url: logURL(),
            records: [metadata(), token(total: 100, at: "2026-03-23T01:00:00Z")]
        )
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        let utc = calendar(timeZone: "UTC")
        let pacific = calendar(timeZone: "America/Los_Angeles")

        let utcSnapshot = try refresh(index, calendar: utc)
        let readsBeforeChange = reader.ranges.count
        let pacificSnapshot = try refresh(index, calendar: pacific)

        XCTAssertGreaterThan(reader.ranges.count, readsBeforeChange)
        XCTAssertEqual(reader.ranges.last?.lowerBound, 0)
        XCTAssertNotEqual(
            utcSnapshot.summaries.first?.dailyCounts.keys.first,
            pacificSnapshot.summaries.first?.dailyCounts.keys.first
        )
    }

    func testFailedCalendarRebuildRetriesThatCursorOnNextRefresh() throws {
        _ = try LogFixture(
            url: logURL(),
            records: [metadata(), token(total: 100, at: "2026-03-23T01:00:00Z")]
        )
        let reader = RecordingRangeReader()
        let index = makeIndex(reader: reader)
        let utcSnapshot = try refresh(index, calendar: calendar(timeZone: "UTC"))

        reader.failingLowerBound = 0
        let failed = try refresh(index, calendar: calendar(timeZone: "America/Los_Angeles"))
        XCTAssertEqual(failed.summaries.first?.dailyCounts.keys.first, utcSnapshot.summaries.first?.dailyCounts.keys.first)
        XCTAssertEqual(failed.warnings.filter { $0.line == 0 }.count, 1)

        reader.failingLowerBound = nil
        let retried = try refresh(index, calendar: calendar(timeZone: "America/Los_Angeles"))
        XCTAssertNotEqual(retried.summaries.first?.dailyCounts.keys.first, utcSnapshot.summaries.first?.dailyCounts.keys.first)
        XCTAssertEqual(reader.ranges.last?.lowerBound, 0)
    }

    func testSessionIndexNameOverlaysSummaryAndRefreshesWithoutLogChanges() throws {
        _ = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let sessionIndexURL = root.appendingPathComponent("session_index.jsonl")
        try Data("{\"id\":\"session-1\",\"thread_name\":\"First name\"}\n".utf8)
            .write(to: sessionIndexURL)
        let index = makeIndex(reader: RecordingRangeReader())

        var snapshot = try index.refresh(
            sessionsDirectory: sessions,
            modifiedSince: .distantPast,
            requiredPaths: [],
            calendar: calendar(timeZone: "UTC"),
            now: now,
            sessionIndexURL: sessionIndexURL
        )
        XCTAssertEqual(snapshot.summaries.first?.session.name, "First name")

        try Data("{\"id\":\"session-1\",\"thread_name\":\"Renamed\"}\n".utf8)
            .write(to: sessionIndexURL, options: .atomic)
        snapshot = try index.refresh(
            sessionsDirectory: sessions,
            modifiedSince: .distantPast,
            requiredPaths: [],
            calendar: calendar(timeZone: "UTC"),
            now: now,
            sessionIndexURL: sessionIndexURL
        )
        XCTAssertEqual(snapshot.summaries.first?.session.name, "Renamed")
    }

    func testOmittedFileCountProducesSafetyWarning() throws {
        _ = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let index = IncrementalCodexLogIndex(
            rangeReader: RecordingRangeReader(),
            discoverer: FileSystemLogDiscoverer(ordinaryLimit: 0)
        )

        let snapshot = try refresh(index)

        XCTAssertEqual(snapshot.omittedFileCount, 1)
        XCTAssertTrue(snapshot.summaries.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.message.contains("10,000-file safety limit") })
    }

    func testPersistentCacheRestoresCursorAndOnlyReadsAppendedBytesAfterRestart() throws {
        let fixture = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let cacheURL = root.appendingPathComponent("cache/log-index.json")
        let firstReader = RecordingRangeReader()
        let firstIndex = IncrementalCodexLogIndex(rangeReader: firstReader, cacheURL: cacheURL)

        let first = try refresh(firstIndex)
        XCTAssertEqual(first.summaries.first?.latestTokenCounts.total, 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        let secondReader = RecordingRangeReader()
        let restoredIndex = IncrementalCodexLogIndex(rangeReader: secondReader, cacheURL: cacheURL)
        let restored = try refresh(restoredIndex)
        XCTAssertTrue(secondReader.ranges.isEmpty)
        XCTAssertEqual(restored.summaries.first?.latestTokenCounts.total, 100)

        let oldSize = fixture.byteSize
        try fixture.append(token(total: 160))
        let appended = try refresh(restoredIndex)
        XCTAssertEqual(secondReader.ranges.last, oldSize..<fixture.byteSize)
        XCTAssertEqual(appended.summaries.first?.latestTokenCounts.total, 160)
        XCTAssertEqual(appended.summaries.first?.dailyCounts.values.first?.total, 160)

        let cacheText = try String(contentsOf: cacheURL, encoding: .utf8)
        for key in ["parserVersion", "inode", "modifiedAt", "size", "parsedOffset", "dailyCounts"] {
            XCTAssertTrue(cacheText.contains("\"\(key)\""), "Missing cache field \(key)")
        }
    }

    func testColdScanRespectsPerFileBudgetAndResumesUntilComplete() throws {
        let records = [metadata()] + (1...20).map { token(total: $0 * 10) }
        _ = try LogFixture(url: logURL(), records: records)
        let reader = RecordingRangeReader()
        let index = IncrementalCodexLogIndex(
            rangeReader: reader,
            chunkSize: 64,
            globalByteBudget: 300,
            perFileByteBudget: 200,
            timeBudget: 10
        )

        var snapshot = try refresh(index)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertEqual(snapshot.pendingFileCount, 1)

        var refreshCount = 1
        while !snapshot.isComplete, refreshCount < 30 {
            snapshot = try refresh(index)
            refreshCount += 1
        }

        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.pendingFileCount, 0)
        XCTAssertEqual(snapshot.summaries.first?.latestTokenCounts.total, 200)
        XCTAssertGreaterThan(refreshCount, 1)
        XCTAssertTrue(reader.ranges.allSatisfy { $0.count <= 200 })
    }

    func testColdScanStopsWhenTimeBudgetExpires() throws {
        let records = [metadata()] + (1...20).map { token(total: $0 * 10) }
        _ = try LogFixture(url: logURL(), records: records)
        let reader = RecordingRangeReader()
        let clock = SequenceClock(values: [0, 0, 1])
        let index = IncrementalCodexLogIndex(
            rangeReader: reader,
            chunkSize: 64,
            timeBudget: 0.5,
            monotonicNow: { clock.next() }
        )

        let snapshot = try refresh(index)

        XCTAssertFalse(snapshot.isComplete)
        XCTAssertEqual(snapshot.pendingFileCount, 1)
        XCTAssertEqual(index.cursorCount, 1)
    }

    func testParserVersionChangeInvalidatesPersistentCache() throws {
        _ = try LogFixture(url: logURL(), records: [metadata(), token(total: 100)])
        let cacheURL = root.appendingPathComponent("cache/versioned-index.json")
        let first = IncrementalCodexLogIndex(
            rangeReader: RecordingRangeReader(),
            cacheURL: cacheURL,
            parserVersion: 1
        )
        _ = try refresh(first)

        let secondReader = RecordingRangeReader()
        let second = IncrementalCodexLogIndex(
            rangeReader: secondReader,
            cacheURL: cacheURL,
            parserVersion: 2
        )
        _ = try refresh(second)

        XCTAssertEqual(secondReader.ranges.first?.lowerBound, 0)
    }

    private func makeIndex(reader: RecordingRangeReader) -> IncrementalCodexLogIndex {
        IncrementalCodexLogIndex(rangeReader: reader)
    }

    private func refresh(
        _ index: IncrementalCodexLogIndex,
        calendar: Calendar? = nil
    ) throws -> IncrementalLogIndexSnapshot {
        try index.refresh(
            sessionsDirectory: sessions,
            modifiedSince: .distantPast,
            requiredPaths: [],
            calendar: calendar ?? self.calendar(timeZone: "UTC"),
            now: now
        )
    }

    private func logURL() -> URL {
        sessions.appendingPathComponent("rollout.jsonl")
    }

    private func metadata(id: String = "session-1") -> String {
        #"{"timestamp":"2026-03-23T00:00:00Z","type":"session_meta","payload":{"id":"\#(id)","cwd":"/tmp/project","source":"cli","originator":"codex-tui","thread_source":"user"}}"#
    }

    private func token(total: Int, at timestamp: String = "2026-03-23T01:00:00Z") -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total)}}}}
        """
    }

    private func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }
}

private final class RecordingRangeReader: FileRangeReading, @unchecked Sendable {
    private(set) var ranges: [Range<UInt64>] = []
    var failingLowerBound: UInt64?

    func read(
        url: URL,
        range: Range<UInt64>,
        chunkSize: Int,
        consume: (Data) throws -> Void
    ) throws {
        ranges.append(range)
        if range.lowerBound == failingLowerBound { throw FixtureError.injectedReadFailure }
        try FileHandleRangeReader().read(url: url, range: range, chunkSize: chunkSize, consume: consume)
    }
}

private final class LogFixture {
    let url: URL

    var byteSize: UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    init(url: URL, records: [String]) throws {
        self.url = url
        try Self.data(records).write(to: url)
    }

    init(url: URL, rawData: Data) throws {
        self.url = url
        try rawData.write(to: url)
    }

    func append(_ record: String) throws {
        try appendRaw(Data((record + "\n").utf8))
    }

    func appendRaw(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func replace(records: [String], atomically: Bool) throws {
        try Self.data(records).write(to: url, options: atomically ? .atomic : [])
    }

    func overwriteByte(at offset: UInt64, with byte: UInt8) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data([byte]))
    }

    private static func data(_ records: [String]) -> Data {
        Data((records.joined(separator: "\n") + "\n").utf8)
    }
}

private enum FixtureError: Error {
    case injectedReadFailure
}

private final class SequenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval]
    private var last: TimeInterval

    init(values: [TimeInterval]) {
        self.values = values
        last = values.last ?? 0
    }

    func next() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return last }
        last = values.removeFirst()
        return last
    }
}
