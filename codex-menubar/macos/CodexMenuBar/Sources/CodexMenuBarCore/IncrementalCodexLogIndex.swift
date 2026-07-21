import Foundation

public struct IncrementalLogIndexSnapshot: Equatable, Sendable {
    public let summaries: [SessionLogSummary]
    public let warnings: [ParseWarning]
    public let omittedFileCount: Int

    public init(
        summaries: [SessionLogSummary],
        warnings: [ParseWarning],
        omittedFileCount: Int = 0
    ) {
        self.summaries = summaries
        self.warnings = warnings
        self.omittedFileCount = omittedFileCount
    }
}

public protocol IncrementalLogIndexing: Sendable {
    func refresh(
        sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>,
        calendar: Calendar,
        now: Date,
        sessionIndexURL: URL?
    ) throws -> IncrementalLogIndexSnapshot
}

public final class IncrementalCodexLogIndex: IncrementalLogIndexing, @unchecked Sendable {
    private struct LogCursor {
        var fingerprint: LogFileFingerprint
        var consumedOffset: UInt64
        var boundaryBytes: Data
        var framing: JSONLFramingState
        var accumulator: SessionLogAccumulator
    }

    private struct CalendarSignature: Equatable {
        let identifier: Calendar.Identifier
        let timeZoneIdentifier: String
    }

    private let rangeReader: any FileRangeReading
    private let discoverer: any LogFileDiscovering
    private let nameIndex: SessionNameIndex
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private let boundaryByteCount: Int
    private let lock = NSLock()
    private var cursors: [String: LogCursor] = [:]
    private var calendarSignature: CalendarSignature?

    public convenience init() {
        self.init(rangeReader: FileHandleRangeReader())
    }

    init(
        rangeReader: any FileRangeReading,
        discoverer: any LogFileDiscovering = FileSystemLogDiscoverer(),
        nameIndex: SessionNameIndex = SessionNameIndex(),
        chunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 8 * 1_024 * 1_024,
        boundaryByteCount: Int = 64
    ) {
        precondition(chunkSize > 0)
        precondition(maximumLineBytes > 0)
        precondition(boundaryByteCount > 0)
        self.rangeReader = rangeReader
        self.discoverer = discoverer
        self.nameIndex = nameIndex
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
        self.boundaryByteCount = boundaryByteCount
    }

    var cursorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cursors.count
    }

    public func refresh(
        sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>,
        calendar inputCalendar: Calendar,
        now: Date,
        sessionIndexURL: URL? = nil
    ) throws -> IncrementalLogIndexSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var calendar = inputCalendar
        calendar.firstWeekday = 2
        let signature = CalendarSignature(
            identifier: calendar.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        let requiresCalendarRebuild = calendarSignature.map { $0 != signature } ?? false
        let discovery = try discoverer.discovery(
            in: sessionsDirectory,
            modifiedSince: modifiedSince,
            requiredPaths: requiredPaths
        )
        let fingerprints = discovery.fingerprints
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -59, to: today)
            ?? now.addingTimeInterval(-59 * 86_400)

        var nextCursors: [String: LogCursor] = [:]
        var refreshWarnings: [ParseWarning] = []

        for fingerprint in fingerprints.sorted(by: { $0.path < $1.path }) {
            let previous = cursors[fingerprint.path]

            if !requiresCalendarRebuild,
               var unchanged = previous,
               unchanged.fingerprint == fingerprint {
                unchanged.accumulator.prune(cutoff: cutoff, today: today)
                nextCursors[fingerprint.path] = unchanged
                continue
            }

            do {
                let next: LogCursor
                if !requiresCalendarRebuild,
                   let previous,
                   canAppend(previous, fingerprint: fingerprint),
                   try boundaryBytesMatch(cursor: previous, url: URL(fileURLWithPath: fingerprint.path)) {
                    next = try consume(
                        cursor: previous,
                        fingerprint: fingerprint,
                        range: previous.consumedOffset..<UInt64(fingerprint.byteSize),
                        cutoff: cutoff,
                        today: today,
                        calendar: calendar
                    )
                } else {
                    let empty = LogCursor(
                        fingerprint: fingerprint,
                        consumedOffset: 0,
                        boundaryBytes: Data(),
                        framing: JSONLFramingState(maximumLineBytes: maximumLineBytes),
                        accumulator: SessionLogAccumulator(path: fingerprint.path)
                    )
                    next = try consume(
                        cursor: empty,
                        fingerprint: fingerprint,
                        range: 0..<UInt64(max(0, fingerprint.byteSize)),
                        cutoff: cutoff,
                        today: today,
                        calendar: calendar
                    )
                }
                nextCursors[fingerprint.path] = next
            } catch {
                refreshWarnings.append(ParseWarning(
                    path: fingerprint.path,
                    line: 0,
                    message: "Unable to read log: \(error.localizedDescription)"
                ))
                if var previous {
                    previous.accumulator.prune(cutoff: cutoff, today: today)
                    nextCursors[fingerprint.path] = previous
                }
            }
        }

        cursors = nextCursors
        calendarSignature = signature
        var sessionNames: [String: String] = [:]
        if let sessionIndexURL {
            do {
                let sessionIDs = Set(cursors.values.compactMap { $0.accumulator.sessionID })
                sessionNames = try nameIndex.names(at: sessionIndexURL, forSessionIDs: sessionIDs)
            } catch {
                refreshWarnings.append(ParseWarning(
                    path: sessionIndexURL.path,
                    line: 0,
                    message: "Unable to read session names: \(error.localizedDescription)"
                ))
            }
        }

        let summaries = cursors.values.map { cursor in
            cursor.accumulator.summary(
                modifiedAt: cursor.fingerprint.modifiedAt,
                threadName: cursor.accumulator.sessionID.flatMap { sessionNames[$0] }
            )
        }.sorted { $0.path < $1.path }
        if discovery.omittedFileCount > 0 {
            refreshWarnings.append(ParseWarning(
                path: sessionsDirectory.path,
                line: 0,
                message: "Skipped \(discovery.omittedFileCount) older session logs after the 10,000-file safety limit."
            ))
        }

        return IncrementalLogIndexSnapshot(
            summaries: summaries,
            warnings: summaries.flatMap(\.warnings) + refreshWarnings,
            omittedFileCount: discovery.omittedFileCount
        )
    }

    private func canAppend(_ cursor: LogCursor, fingerprint: LogFileFingerprint) -> Bool {
        cursor.fingerprint.identity == fingerprint.identity
            && fingerprint.byteSize >= 0
            && UInt64(fingerprint.byteSize) > cursor.consumedOffset
    }

    private func boundaryBytesMatch(cursor: LogCursor, url: URL) throws -> Bool {
        guard !cursor.boundaryBytes.isEmpty else { return true }
        let start = cursor.consumedOffset - UInt64(cursor.boundaryBytes.count)
        var bytes = Data()
        try rangeReader.read(
            url: url,
            range: start..<cursor.consumedOffset,
            chunkSize: chunkSize
        ) { bytes.append($0) }
        return bytes == cursor.boundaryBytes
    }

    private func consume(
        cursor: LogCursor,
        fingerprint: LogFileFingerprint,
        range: Range<UInt64>,
        cutoff: Date,
        today: Date,
        calendar: Calendar
    ) throws -> LogCursor {
        var next = cursor
        var tail = cursor.boundaryBytes
        let url = URL(fileURLWithPath: fingerprint.path)

        try rangeReader.read(url: url, range: range, chunkSize: chunkSize) { data in
            tail.append(data)
            if tail.count > boundaryByteCount {
                tail = Data(tail.suffix(boundaryByteCount))
            }

            let output = next.framing.consume(data, path: fingerprint.path)
            for warning in output.warnings {
                next.accumulator.consume(warning: warning)
            }
            for record in output.records {
                next.accumulator.consume(
                    record: record,
                    modifiedAt: fingerprint.modifiedAt,
                    cutoff: cutoff,
                    today: today,
                    calendar: calendar
                )
            }
        }

        next.fingerprint = fingerprint
        next.consumedOffset = range.upperBound
        next.boundaryBytes = tail
        next.accumulator.prune(cutoff: cutoff, today: today)
        return next
    }
}
