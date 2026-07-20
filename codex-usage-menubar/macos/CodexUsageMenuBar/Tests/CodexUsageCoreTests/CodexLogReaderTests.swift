import XCTest
@testable import CodexUsageCore

final class CodexLogReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var reader: CodexLogReader!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMenuBarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        reader = CodexLogReader()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsPrimaryAndSecondaryRemaining() throws {
        let session = tempDirectory.appendingPathComponent("2026/07/05/session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 12, usedSecondary: 4)], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.label, "5h")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 88)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 96)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.creditsDescription, "none")
    }

    func testSkipsBadJsonAndUsesOlderValidEvent() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 45, usedSecondary: 10), "{bad json"], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.remainingPercent, 55)
    }

    func testSelectsNewestEventTimestampAcrossFiles() throws {
        let newerFileMtimeOlderEvent = tempDirectory.appendingPathComponent("newer-file-mtime.jsonl")
        try write(records: [tokenCountEvent(
            usedPrimary: 90,
            usedSecondary: 10,
            timestamp: "2026-07-03T04:38:11.000Z"
        )], to: newerFileMtimeOlderEvent)
        try setModificationDate(Date(timeIntervalSince1970: 1_800_000_000), for: newerFileMtimeOlderEvent)

        let olderFileMtimeNewerEvent = tempDirectory.appendingPathComponent("older-file-mtime.jsonl")
        try write(records: [tokenCountEvent(
            usedPrimary: 20,
            usedSecondary: 10,
            timestamp: "2026-07-04T04:38:11.000Z"
        )], to: olderFileMtimeNewerEvent)
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_000), for: olderFileMtimeNewerEvent)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(
            URL(fileURLWithPath: snapshot.sourcePath).resolvingSymlinksInPath().path,
            olderFileMtimeNewerEvent.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(snapshot.primary?.remainingPercent, 80)
    }

    func testUsesFileModificationDateWhenEventTimestampIsMissing() throws {
        let olderSession = tempDirectory.appendingPathComponent("older.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 70, usedSecondary: 10, timestamp: nil)], to: olderSession)
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_000), for: olderSession)

        let newerSession = tempDirectory.appendingPathComponent("newer.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 30, usedSecondary: 10, timestamp: nil)], to: newerSession)
        try setModificationDate(Date(timeIntervalSince1970: 1_800_000_000), for: newerSession)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(
            URL(fileURLWithPath: snapshot.sourcePath).resolvingSymlinksInPath().path,
            newerSession.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(snapshot.primary?.remainingPercent, 70)
    }

    func testUnreadableSessionsDirectoryReturnsUnableToReadFailure() throws {
        let unreadable = tempDirectory.appendingPathComponent("unreadable")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }

        guard !FileManager.default.isReadableFile(atPath: unreadable.path) else {
            throw XCTSkip("chmod 000 directory is still readable in this environment")
        }

        let result = reader.readLatestSnapshot(sessionsDirectory: unreadable)

        guard case let .failure(error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error.menuValue, "!")
        XCTAssertEqual(error.message, "Unable to read Codex session logs")
        XCTAssertTrue(error.detail?.contains("Directory is not readable") == true)
        XCTAssertTrue(error.detail?.contains(unreadable.path) == true)
    }

    func testMissingSessionsDirectoryReturnsFailure() {
        let missing = tempDirectory.appendingPathComponent("missing")

        let result = reader.readLatestSnapshot(sessionsDirectory: missing)

        XCTAssertEqual(result, .failure(UsageReadError(
            menuValue: "--",
            message: "No Codex session directory found",
            detail: missing.path
        )))
    }

    func testNoRateLimitEventReturnsFailure() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [#"{"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .failure(error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error.menuValue, "--")
        XCTAssertTrue(error.message.contains("No rate limit event"))
    }

    func testUnexpectedCreditsBalanceTypeDoesNotSkipUsageRecord() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [tokenCountEvent(
            usedPrimary: 25,
            usedSecondary: 40,
            creditsBalanceJSON: #"{"unexpected":true}"#,
            hasCredits: true
        )], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.remainingPercent, 75)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 60)
        XCTAssertEqual(snapshot.creditsDescription, "available")
    }

    func testUnexpectedWindowNumericTypesDoNotSkipUsageRecord() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [
            """
            {"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":{"unexpected":true},"resets_at":["soon"]},"secondary":{"used_percent":"40","window_minutes":"10080","resets_at":"1783630800"},"credits":{"has_credits":"true","unlimited":"false","balance":"12"},"plan_type":"plus"}}}
            """
        ], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.label, "--")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 75)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 60)
        XCTAssertEqual(snapshot.creditsDescription, "12")
    }

    func testNonFiniteWindowStringsDecodeAsNilWithoutSkippingRecord() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [
            """
            {"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"NaN","window_minutes":"Infinity","resets_at":"inf"},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1783630800},"credits":{"has_credits":true,"unlimited":false,"balance":"Infinity"},"plan_type":"plus"}}}
            """
        ], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.label, "--")
        XCTAssertNil(snapshot.primary?.remainingPercent)
        XCTAssertNil(snapshot.primary?.resetsAt)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 60)
        XCTAssertEqual(snapshot.creditsDescription, "available")
    }

    func testOversizedNumericCreditsBalanceDoesNotSkipUsageRecord() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [
            """
            {"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1783070400},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1783630800},"credits":{"has_credits":true,"unlimited":false,"balance":92233720368547758070},"plan_type":"plus"}}}
            """
        ], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.remainingPercent, 75)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 60)
        XCTAssertEqual(snapshot.creditsDescription, "available")
    }

    func testFormattingHelpers() {
        XCTAssertNil(UsageFormatting.remainingFromUsed(nil))
        XCTAssertNil(UsageFormatting.remainingFromUsed(.nan))
        XCTAssertNil(UsageFormatting.remainingFromUsed(.infinity))
        XCTAssertEqual(UsageFormatting.remainingFromUsed(-10), 100)
        XCTAssertEqual(UsageFormatting.remainingFromUsed(12.4), 88)
        XCTAssertEqual(UsageFormatting.remainingFromUsed(120), 0)

        XCTAssertEqual(UsageFormatting.menuLabel(nil), "--")
        XCTAssertEqual(UsageFormatting.menuLabel(-10), "0")
        XCTAssertEqual(UsageFormatting.menuLabel(42), "42")
        XCTAssertEqual(UsageFormatting.menuLabel(120), "100")

        XCTAssertEqual(UsageFormatting.percentLabel(nil), "--")
        XCTAssertEqual(UsageFormatting.percentLabel(42), "42%")

        XCTAssertEqual(UsageFormatting.windowLabel(minutes: nil), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: .nan), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: .infinity), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: Double(Int.max)), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 45), "45m")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 60), "1h")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 300), "5h")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 1_440), "1d")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 10_080), "7d")
    }

    func testDateLabelUsesSameDayTimeFormat() throws {
        let calendar = utcCalendar()
        let date = try isoDate("2026-07-05T13:38:30Z")
        let now = try isoDate("2026-07-05T23:59:00Z")

        XCTAssertEqual(UsageFormatting.dateLabel(date, calendar: calendar, now: now), "13:38:30")
    }

    func testDateLabelUsesMonthDayTimeFormatForDifferentDay() throws {
        let calendar = utcCalendar()
        let date = try isoDate("2026-07-04T13:38:30Z")
        let now = try isoDate("2026-07-05T00:00:00Z")

        XCTAssertEqual(UsageFormatting.dateLabel(date, calendar: calendar, now: now), "Jul 4 13:38")
    }

    private func write(records: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try records.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func tokenCountEvent(
        usedPrimary: Int,
        usedSecondary: Int,
        timestamp: String? = "2026-07-03T04:38:11.000Z",
        creditsBalanceJSON: String = "null",
        hasCredits: Bool = false
    ) -> String {
        let timestampField = timestamp.map { #""timestamp":"\#($0)","# } ?? ""
        return """
        {\(timestampField)"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\(usedPrimary),"window_minutes":300,"resets_at":1783070400},"secondary":{"used_percent":\(usedSecondary),"window_minutes":10080,"resets_at":1783630800},"credits":{"has_credits":\(hasCredits),"unlimited":false,"balance":\(creditsBalanceJSON)},"plan_type":"plus"}}}
        """
    }
}
