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
