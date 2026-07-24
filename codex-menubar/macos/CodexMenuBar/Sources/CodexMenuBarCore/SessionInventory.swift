import Foundation

public final class SessionInventory: @unchecked Sendable {
    private struct CachedAssociation {
        let processStartedAt: Date
        var logPaths: Set<String>
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
        let cached = cachedAssociationByPID.flatMap { pid, association -> [String] in
            starts[pid] == association.processStartedAt ? Array(association.logPaths) : []
        }
        return Set(candidates.flatMap(\.openFilePaths) + cached)
    }

    public func read(summaries: [SessionLogSummary], now: Date) -> SessionInventoryResult {
        do {
            return read(summaries: summaries, candidates: try scanProcesses(), now: now)
        } catch {
            return .failure(SessionInventoryError(
                message: "Unable to scan Codex processes",
                detail: error.localizedDescription
            ))
        }
    }

    public func read(
        summaries: [SessionLogSummary],
        candidates: [ProcessSnapshot],
        now: Date
    ) -> SessionInventoryResult {
        lock.lock()
        defer { lock.unlock() }

        let processStartByPID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.pid, $0.startedAt) })
        cachedAssociationByPID = cachedAssociationByPID.filter { pid, association in
            processStartByPID[pid] == association.processStartedAt
        }

        let eligibleLogs = summaries.filter(\.isTopLevelLiveSession)
        let logsByPath = Dictionary(uniqueKeysWithValues: eligibleLogs.map {
            (URL(fileURLWithPath: $0.path).standardizedFileURL.path, $0)
        })
        var assignedPaths = Set<String>()
        var snapshots: [SessionDisplaySnapshot] = []
        var unresolved: [ProcessSnapshot] = []

        for process in candidates {
            let openPaths = process.openFilePaths
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                .sorted()
            let matches = openPaths.filter {
                !assignedPaths.contains($0) && logsByPath[$0] != nil
            }
            for match in matches {
                guard let log = logsByPath[match] else { continue }
                assignedPaths.insert(match)
                cache(logPath: match, for: process)
                snapshots.append(displaySnapshot(process: process, log: log, now: now))
            }
            if matches.isEmpty {
                unresolved.append(process)
            }
        }

        var needsFallback: [ProcessSnapshot] = []
        for process in unresolved {
            guard let association = cachedAssociationByPID[process.pid] else {
                cachedAssociationByPID.removeValue(forKey: process.pid)
                needsFallback.append(process)
                continue
            }
            let cachedPaths = association.logPaths.sorted().filter {
                !assignedPaths.contains($0) && logsByPath[$0] != nil
            }
            guard !cachedPaths.isEmpty else {
                cachedAssociationByPID.removeValue(forKey: process.pid)
                needsFallback.append(process)
                continue
            }
            for cachedPath in cachedPaths {
                guard let log = logsByPath[cachedPath] else { continue }
                assignedPaths.insert(cachedPath)
                snapshots.append(displaySnapshot(process: process, log: log, now: now))
            }
        }

        for process in needsFallback {
            guard let log = fallbackMatch(
                for: process,
                logs: eligibleLogs,
                excluding: assignedPaths
            ) else {
                if !classifier.isDesktopAppServer(process) {
                    snapshots.append(unassociatedSnapshot(process: process))
                }
                continue
            }
            let path = URL(fileURLWithPath: log.path).standardizedFileURL.path
            assignedPaths.insert(path)
            cache(logPath: path, for: process)
            snapshots.append(displaySnapshot(process: process, log: log, now: now))
        }

        return .snapshots(snapshots.sorted(by: displayOrder))
    }

    private func fallbackMatch(
        for process: ProcessSnapshot,
        logs: [SessionLogSummary],
        excluding assignedPaths: Set<String>
    ) -> SessionLogSummary? {
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
        if var existing = cachedAssociationByPID[process.pid],
           existing.processStartedAt == process.startedAt
        {
            existing.logPaths.insert(logPath)
            cachedAssociationByPID[process.pid] = existing
        } else {
            cachedAssociationByPID[process.pid] = CachedAssociation(
                processStartedAt: process.startedAt,
                logPaths: [logPath]
            )
        }
    }

    private func displaySnapshot(
        process: ProcessSnapshot,
        log: SessionLogSummary,
        now: Date
    ) -> SessionDisplaySnapshot {
        let activity: SessionActivity = log.lifecycle == .active
            && now.timeIntervalSince(log.modifiedAt) < 300
            ? .running
            : .stalled
        let taskDescription = log.session.name
        return SessionDisplaySnapshot(
            pid: process.pid,
            sessionID: log.session.id,
            sourceKind: log.session.sourceKind,
            activity: activity,
            taskDescription: taskDescription,
            displayTaskDescription: SessionTextFormatting.displayDescription(taskDescription),
            workingDirectory: log.session.workingDirectory
                ?? process.workingDirectory
                ?? "Unknown working directory",
            sourcePath: log.path,
            lastUpdatedAt: log.modifiedAt,
            tokenCounts: log.latestTokenCounts
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
