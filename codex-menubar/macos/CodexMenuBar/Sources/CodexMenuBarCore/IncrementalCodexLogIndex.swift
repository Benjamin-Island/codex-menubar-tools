import Foundation

public struct IncrementalLogIndexSnapshot: Equatable, Sendable {
    public let summaries: [SessionLogSummary]
    public let warnings: [ParseWarning]
    public let omittedFileCount: Int
    public let isComplete: Bool
    public let pendingFileCount: Int

    public init(
        summaries: [SessionLogSummary],
        warnings: [ParseWarning],
        omittedFileCount: Int = 0,
        isComplete: Bool = true,
        pendingFileCount: Int = 0
    ) {
        self.summaries = summaries
        self.warnings = warnings
        self.omittedFileCount = omittedFileCount
        self.isComplete = isComplete
        self.pendingFileCount = pendingFileCount
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
    private static let currentParserVersion = 1

    private struct LogCursor {
        var fingerprint: LogFileFingerprint
        var calendarSignature: CalendarSignature
        var consumedOffset: UInt64
        var boundaryBytes: Data
        var framing: JSONLFramingState
        var accumulator: SessionLogAccumulator
    }

    private struct CalendarSignature: Equatable {
        let identifier: String
        let timeZoneIdentifier: String
    }

    private struct PersistentCache: Codable {
        let parserVersion: Int
        let entries: [PersistentEntry]
    }

    private struct PersistentEntry: Codable {
        let path: String
        let device: UInt64
        let inode: UInt64
        let modifiedAt: Date
        let size: Int64
        let parsedOffset: UInt64
        let boundaryBytes: Data
        let framing: JSONLFramingState
        let accumulator: SessionLogAccumulator
        let calendarIdentifier: String
        let timeZoneIdentifier: String
    }

    private enum ScanStop: Error {
        case timeBudgetReached
    }

    private struct ConsumeResult {
        let cursor: LogCursor
        let bytesConsumed: UInt64
        let timeBudgetReached: Bool
    }

    private let rangeReader: any FileRangeReading
    private let discoverer: any LogFileDiscovering
    private let nameIndex: SessionNameIndex
    private let metadataReader: SessionMetadataReader
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private let boundaryByteCount: Int
    private let globalByteBudget: UInt64
    private let perFileByteBudget: UInt64
    private let timeBudget: TimeInterval
    private let monotonicNow: @Sendable () -> TimeInterval
    private let cacheURL: URL?
    private let parserVersion: Int
    private let lock = NSLock()
    private var cursors: [String: LogCursor] = [:]
    private var didLoadCache = false

    public convenience init() {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let cacheURL = cacheRoot?
            .appendingPathComponent("CodexMenuBar", isDirectory: true)
            .appendingPathComponent("log-index-v1.json")
        self.init(rangeReader: FileHandleRangeReader(), cacheURL: cacheURL)
    }

    public static func todayUsageIndex() -> IncrementalCodexLogIndex {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let cacheURL = cacheRoot?
            .appendingPathComponent("CodexMenuBar", isDirectory: true)
            .appendingPathComponent("today-index-v1.json")
        return IncrementalCodexLogIndex(
            rangeReader: FileHandleRangeReader(),
            globalByteBudget: 16 * 1_024 * 1_024,
            perFileByteBudget: 16 * 1_024 * 1_024,
            timeBudget: 0.1,
            cacheURL: cacheURL
        )
    }

    init(
        rangeReader: any FileRangeReading,
        discoverer: any LogFileDiscovering = FileSystemLogDiscoverer(),
        nameIndex: SessionNameIndex = SessionNameIndex(),
        metadataReader: SessionMetadataReader = SessionMetadataReader(),
        chunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 8 * 1_024 * 1_024,
        boundaryByteCount: Int = 64,
        globalByteBudget: UInt64 = 64 * 1_024 * 1_024,
        perFileByteBudget: UInt64 = 16 * 1_024 * 1_024,
        timeBudget: TimeInterval = 0.5,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        cacheURL: URL? = nil,
        parserVersion: Int = IncrementalCodexLogIndex.currentParserVersion
    ) {
        precondition(chunkSize > 0)
        precondition(maximumLineBytes > 0)
        precondition(boundaryByteCount > 0)
        precondition(globalByteBudget > 0)
        precondition(perFileByteBudget > 0)
        precondition(timeBudget > 0)
        self.rangeReader = rangeReader
        self.discoverer = discoverer
        self.nameIndex = nameIndex
        self.metadataReader = metadataReader
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
        self.boundaryByteCount = boundaryByteCount
        self.globalByteBudget = globalByteBudget
        self.perFileByteBudget = perFileByteBudget
        self.timeBudget = timeBudget
        self.monotonicNow = monotonicNow
        self.cacheURL = cacheURL
        self.parserVersion = parserVersion
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
            identifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        loadCacheIfNeeded(signature: signature)
        let discovery = try discoverer.discovery(
            in: sessionsDirectory,
            modifiedSince: modifiedSince,
            requiredPaths: requiredPaths
        )
        let fingerprints = discovery.fingerprints
        let today = calendar.startOfDay(for: now)
        let cutoff = HistoryWindow.start(calendar: calendar, now: now)

        var nextCursors: [String: LogCursor] = [:]
        var refreshWarnings: [ParseWarning] = []
        var remainingByteBudget = globalByteBudget
        let deadline = monotonicNow() + timeBudget
        var timeBudgetReached = false
        let standardizedRequiredPaths = Set(requiredPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })

        let orderedFingerprints = fingerprints.sorted {
            let lhsRequired = standardizedRequiredPaths.contains($0.path)
            let rhsRequired = standardizedRequiredPaths.contains($1.path)
            if lhsRequired != rhsRequired { return lhsRequired }
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.path < $1.path
        }
        for fingerprint in orderedFingerprints {
            if monotonicNow() >= deadline {
                timeBudgetReached = true
            }
            let previous = cursors[fingerprint.path]
            let requiresCalendarRebuild = previous.map {
                $0.calendarSignature != signature
            } ?? false

            if !requiresCalendarRebuild,
               var unchanged = previous,
               unchanged.fingerprint == fingerprint,
               unchanged.consumedOffset == UInt64(max(0, fingerprint.byteSize)) {
                unchanged.accumulator.prune(cutoff: cutoff, today: today)
                nextCursors[fingerprint.path] = unchanged
                continue
            }

            guard remainingByteBudget > 0, !timeBudgetReached else {
                if var previous {
                    previous.accumulator.prune(cutoff: cutoff, today: today)
                    nextCursors[fingerprint.path] = previous
                }
                continue
            }

            do {
                let baseCursor: LogCursor
                let lowerBound: UInt64
                if !requiresCalendarRebuild,
                   let previous,
                   canAppend(previous, fingerprint: fingerprint),
                   try boundaryBytesMatch(cursor: previous, url: URL(fileURLWithPath: fingerprint.path)) {
                    baseCursor = previous
                    lowerBound = previous.consumedOffset
                } else {
                    var accumulator = SessionLogAccumulator(path: fingerprint.path)
                    if let metadataRecord = metadataReader.firstRecord(
                        at: URL(fileURLWithPath: fingerprint.path)
                    ) {
                        accumulator.consume(
                            record: metadataRecord,
                            modifiedAt: fingerprint.modifiedAt,
                            cutoff: cutoff,
                            today: today,
                            calendar: calendar
                        )
                    }
                    baseCursor = LogCursor(
                        fingerprint: fingerprint,
                        calendarSignature: signature,
                        consumedOffset: 0,
                        boundaryBytes: Data(),
                        framing: JSONLFramingState(maximumLineBytes: maximumLineBytes),
                        accumulator: accumulator
                    )
                    lowerBound = 0
                }
                let fileUpperBound = UInt64(max(0, fingerprint.byteSize))
                let available = fileUpperBound > lowerBound ? fileUpperBound - lowerBound : 0
                let scanLength = min(available, perFileByteBudget, remainingByteBudget)
                let result = try consume(
                    cursor: baseCursor,
                    fingerprint: fingerprint,
                    calendarSignature: signature,
                    range: lowerBound..<(lowerBound + scanLength),
                    cutoff: cutoff,
                    today: today,
                    calendar: calendar,
                    deadline: deadline
                )
                nextCursors[fingerprint.path] = result.cursor
                remainingByteBudget -= result.bytesConsumed
                timeBudgetReached = result.timeBudgetReached
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
        persistCache()
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

        let pendingFileCount = fingerprints.reduce(into: 0) { count, fingerprint in
            let expectedOffset = UInt64(max(0, fingerprint.byteSize))
            if nextCursors[fingerprint.path]?.consumedOffset != expectedOffset {
                count += 1
            }
        }
        return IncrementalLogIndexSnapshot(
            summaries: summaries,
            warnings: summaries.flatMap(\.warnings) + refreshWarnings,
            omittedFileCount: discovery.omittedFileCount,
            isComplete: pendingFileCount == 0,
            pendingFileCount: pendingFileCount
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
        calendarSignature: CalendarSignature,
        range: Range<UInt64>,
        cutoff: Date,
        today: Date,
        calendar: Calendar,
        deadline: TimeInterval
    ) throws -> ConsumeResult {
        var next = cursor
        var tail = cursor.boundaryBytes
        let url = URL(fileURLWithPath: fingerprint.path)
        var consumedOffset = range.lowerBound
        var stoppedForTime = false

        do {
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
                consumedOffset += UInt64(data.count)
                if consumedOffset < range.upperBound, monotonicNow() >= deadline {
                    throw ScanStop.timeBudgetReached
                }
            }
        } catch ScanStop.timeBudgetReached {
            stoppedForTime = true
        }

        next.fingerprint = fingerprint
        next.calendarSignature = calendarSignature
        next.consumedOffset = consumedOffset
        next.boundaryBytes = tail
        next.accumulator.prune(cutoff: cutoff, today: today)
        return ConsumeResult(
            cursor: next,
            bytesConsumed: consumedOffset - range.lowerBound,
            timeBudgetReached: stoppedForTime
        )
    }

    private func loadCacheIfNeeded(signature: CalendarSignature) {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(PersistentCache.self, from: data),
              cache.parserVersion == parserVersion
        else {
            return
        }
        cursors = Dictionary(uniqueKeysWithValues: cache.entries.compactMap { entry in
            guard entry.calendarIdentifier == signature.identifier,
                  entry.timeZoneIdentifier == signature.timeZoneIdentifier
            else {
                return nil
            }
            let fingerprint = LogFileFingerprint(
                path: entry.path,
                modifiedAt: entry.modifiedAt,
                byteSize: entry.size,
                identity: LogFileIdentity(device: entry.device, inode: entry.inode)
            )
            return (entry.path, LogCursor(
                fingerprint: fingerprint,
                calendarSignature: signature,
                consumedOffset: entry.parsedOffset,
                boundaryBytes: entry.boundaryBytes,
                framing: entry.framing,
                accumulator: entry.accumulator
            ))
        })
    }

    private func persistCache() {
        guard let cacheURL else { return }
        let entries = cursors.values.map { cursor in
            PersistentEntry(
                path: cursor.fingerprint.path,
                device: cursor.fingerprint.identity.device,
                inode: cursor.fingerprint.identity.inode,
                modifiedAt: cursor.fingerprint.modifiedAt,
                size: cursor.fingerprint.byteSize,
                parsedOffset: cursor.consumedOffset,
                boundaryBytes: cursor.boundaryBytes,
                framing: cursor.framing,
                accumulator: cursor.accumulator,
                calendarIdentifier: cursor.calendarSignature.identifier,
                timeZoneIdentifier: cursor.calendarSignature.timeZoneIdentifier
            )
        }.sorted { $0.path < $1.path }
        let cache = PersistentCache(parserVersion: parserVersion, entries: entries)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }
}
