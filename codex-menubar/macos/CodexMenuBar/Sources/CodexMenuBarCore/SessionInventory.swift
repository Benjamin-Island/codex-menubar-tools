import Foundation

public final class SessionInventory: @unchecked Sendable {
    private struct CachedAssociation {
        let processStartedAt: Date
        let logPath: String
    }

    private let processProvider: any ProcessProviding
    private let classifier: InteractiveTUIClassifier
    private let currentUID: UInt32
    private let lock = NSLock()
    private var cachedAssociationByPID: [Int32: CachedAssociation] = [:]

    public init(
        processProvider: any ProcessProviding,
        classifier: InteractiveTUIClassifier,
        currentUID: UInt32
    ) {
        self.processProvider = processProvider
        self.classifier = classifier
        self.currentUID = currentUID
    }

    public func scanProcesses() throws -> [ProcessSnapshot] {
        classifier.candidates(
            from: try processProvider.processSnapshots(),
            currentUID: currentUID
        )
    }

    public func requiredLogPaths(for candidates: [ProcessSnapshot]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let starts = Dictionary(uniqueKeysWithValues: candidates.map { ($0.pid, $0.startedAt) })
        let cached = cachedAssociationByPID.compactMap { pid, association -> String? in
            starts[pid] == association.processStartedAt ? association.logPath : nil
        }
        return Set(candidates.flatMap(\.openFilePaths) + cached)
    }

    public func read(logs: [IndexedSessionLog], now: Date) -> SessionInventoryResult {
        do {
            return read(logs: logs, candidates: try scanProcesses(), now: now)
        } catch {
            return .failure(SessionInventoryError(
                message: "Unable to scan Codex CLI processes",
                detail: error.localizedDescription
            ))
        }
    }

    public func read(
        logs: [IndexedSessionLog],
        candidates: [ProcessSnapshot],
        now: Date
    ) -> SessionInventoryResult {
        lock.lock()
        defer { lock.unlock() }

        let processStartByPID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.pid, $0.startedAt) })
        cachedAssociationByPID = cachedAssociationByPID.filter { pid, association in
            processStartByPID[pid] == association.processStartedAt
        }

        let eligibleLogs = logs.filter(\.isTopLevelInteractiveTUI)
        let logsByPath = Dictionary(uniqueKeysWithValues: eligibleLogs.map {
            (URL(fileURLWithPath: $0.path).standardizedFileURL.path, $0)
        })
        var assignedPaths = Set<String>()
        var snapshotsByPID: [Int32: SessionDisplaySnapshot] = [:]
        var unresolved: [ProcessSnapshot] = []

        for process in candidates {
            let openPaths = process.openFilePaths
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                .sorted()
            if let match = openPaths.first(where: {
                !assignedPaths.contains($0) && logsByPath[$0] != nil
            }),
               let log = logsByPath[match]
            {
                assignedPaths.insert(match)
                cache(logPath: match, for: process)
                snapshotsByPID[process.pid] = displaySnapshot(process: process, log: log, now: now)
            } else {
                unresolved.append(process)
            }
        }

        var needsFallback: [ProcessSnapshot] = []
        for process in unresolved {
            guard let cachedPath = cachedAssociationByPID[process.pid]?.logPath,
                  !assignedPaths.contains(cachedPath),
                  let log = logsByPath[cachedPath]
            else {
                cachedAssociationByPID.removeValue(forKey: process.pid)
                needsFallback.append(process)
                continue
            }
            assignedPaths.insert(cachedPath)
            snapshotsByPID[process.pid] = displaySnapshot(process: process, log: log, now: now)
        }

        for process in needsFallback {
            guard let log = fallbackMatch(
                for: process,
                logs: eligibleLogs,
                excluding: assignedPaths
            ) else {
                snapshotsByPID[process.pid] = unassociatedSnapshot(process: process)
                continue
            }
            let path = URL(fileURLWithPath: log.path).standardizedFileURL.path
            assignedPaths.insert(path)
            cache(logPath: path, for: process)
            snapshotsByPID[process.pid] = displaySnapshot(process: process, log: log, now: now)
        }

        let items = candidates
            .compactMap { snapshotsByPID[$0.pid] }
            .sorted(by: displayOrder)
        return .snapshots(items)
    }

    private func fallbackMatch(
        for process: ProcessSnapshot,
        logs: [IndexedSessionLog],
        excluding assignedPaths: Set<String>
    ) -> IndexedSessionLog? {
        guard let cwd = process.workingDirectory else { return nil }
        return logs.filter { log in
            let path = URL(fileURLWithPath: log.path).standardizedFileURL.path
            guard !assignedPaths.contains(path),
                  log.session.workingDirectory == cwd,
                  let timestamp = log.metadataTimestamp
            else {
                return false
            }
            let offset = timestamp.timeIntervalSince(process.startedAt)
            return offset >= 0 && offset <= 120
        }.min { lhs, rhs in
            let lhsOffset = lhs.metadataTimestamp!.timeIntervalSince(process.startedAt)
            let rhsOffset = rhs.metadataTimestamp!.timeIntervalSince(process.startedAt)
            if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
            return lhs.path < rhs.path
        }
    }

    private func cache(logPath: String, for process: ProcessSnapshot) {
        cachedAssociationByPID[process.pid] = CachedAssociation(
            processStartedAt: process.startedAt,
            logPath: logPath
        )
    }

    private func displaySnapshot(
        process: ProcessSnapshot,
        log: IndexedSessionLog,
        now: Date
    ) -> SessionDisplaySnapshot {
        let activity: SessionActivity = log.lifecycle == .active
            && now.timeIntervalSince(log.modifiedAt) < 300
            ? .running
            : .stalled
        let latestCounts = log.tokenEvents.max { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.sequence < rhs.sequence
        }?.cumulative ?? .zero
        let taskDescription = log.session.name
        return SessionDisplaySnapshot(
            pid: process.pid,
            sessionID: log.session.id,
            activity: activity,
            taskDescription: taskDescription,
            displayTaskDescription: SessionTextFormatting.displayDescription(taskDescription),
            workingDirectory: log.session.workingDirectory
                ?? process.workingDirectory
                ?? "Unknown working directory",
            sourcePath: log.path,
            lastUpdatedAt: log.modifiedAt,
            tokenCounts: latestCounts
        )
    }

    private func unassociatedSnapshot(process: ProcessSnapshot) -> SessionDisplaySnapshot {
        let workingDirectory = process.workingDirectory ?? "Unknown working directory"
        let directoryName = process.workingDirectory.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        let taskDescription = directoryName.flatMap { $0.isEmpty ? nil : $0 } ?? "Codex CLI"
        return SessionDisplaySnapshot(
            pid: process.pid,
            sessionID: nil,
            activity: .stalled,
            taskDescription: taskDescription,
            displayTaskDescription: SessionTextFormatting.displayDescription(taskDescription),
            workingDirectory: workingDirectory,
            sourcePath: nil,
            lastUpdatedAt: nil,
            tokenCounts: .zero
        )
    }

    private func displayOrder(_ lhs: SessionDisplaySnapshot, _ rhs: SessionDisplaySnapshot) -> Bool {
        if lhs.activity != rhs.activity { return lhs.activity == .running }
        let comparison = lhs.taskDescription.localizedCaseInsensitiveCompare(rhs.taskDescription)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.pid < rhs.pid
    }
}
