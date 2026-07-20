import Foundation

public final class SessionInventory: @unchecked Sendable {
    private let processProvider: any ProcessProviding
    private let classifier: InteractiveTUIClassifier
    private let logReader: CodexSessionLogReader
    private let sessionsDirectory: URL
    private let sessionIndexURL: URL
    private let currentUID: UInt32
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()
    private struct CachedAssociation {
        let processStartedAt: Date
        let logPath: String
    }

    private var cachedAssociationByPID: [Int32: CachedAssociation] = [:]

    public init(
        processProvider: any ProcessProviding,
        classifier: InteractiveTUIClassifier,
        logReader: CodexSessionLogReader,
        sessionsDirectory: URL,
        sessionIndexURL: URL,
        currentUID: UInt32,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.processProvider = processProvider
        self.classifier = classifier
        self.logReader = logReader
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexURL = sessionIndexURL
        self.currentUID = currentUID
        self.now = now
        fileManager = .default
    }

    public func read() -> SessionInventoryResult {
        lock.lock()
        defer { lock.unlock() }

        let processes: [ProcessSnapshot]
        do {
            processes = try processProvider.processSnapshots()
        } catch {
            return .failure(SessionInventoryError(
                message: "无法扫描 Codex CLI 进程",
                detail: error.localizedDescription
            ))
        }

        let candidates = classifier.candidates(from: processes, currentUID: currentUID)
        let processStartByPID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.pid, $0.startedAt) })
        cachedAssociationByPID = cachedAssociationByPID.filter { pid, association in
            processStartByPID[pid] == association.processStartedAt
        }

        do {
            let names = try logReader.readSessionNames(at: sessionIndexURL)
            let items = try buildSnapshots(for: candidates, sessionNames: names)
            return .snapshots(items.sorted(by: displayOrder))
        } catch {
            return .failure(SessionInventoryError(
                message: "无法读取 Codex 会话",
                detail: error.localizedDescription
            ))
        }
    }

    private func buildSnapshots(
        for processes: [ProcessSnapshot],
        sessionNames: [String: String]
    ) throws -> [SessionDisplaySnapshot] {
        var assignedPaths = Set<String>()
        var snapshotsByPID: [Int32: SessionDisplaySnapshot] = [:]
        var unresolved: [ProcessSnapshot] = []

        for process in processes {
            if let match = directMatch(
                for: process,
                sessionNames: sessionNames,
                excluding: assignedPaths
            ) {
                assignedPaths.insert(match.log.sourcePath)
                cache(logPath: match.log.sourcePath, for: process)
                snapshotsByPID[process.pid] = displaySnapshot(process: process, log: match.log)
            } else {
                unresolved.append(process)
            }
        }

        var needsFallback: [ProcessSnapshot] = []
        for process in unresolved {
            guard let cachedPath = cachedAssociationByPID[process.pid]?.logPath,
                  !assignedPaths.contains(cachedPath),
                  let log = readLog(atPath: cachedPath, sessionNames: sessionNames)
            else {
                cachedAssociationByPID.removeValue(forKey: process.pid)
                needsFallback.append(process)
                continue
            }
            assignedPaths.insert(log.sourcePath)
            snapshotsByPID[process.pid] = displaySnapshot(process: process, log: log)
        }

        if !needsFallback.isEmpty {
            let metadataRecords = try scanMetadata(excluding: assignedPaths)
            for process in needsFallback {
                guard let match = fallbackMatch(
                    for: process,
                    records: metadataRecords,
                    excluding: assignedPaths
                ),
                let log = readLog(atPath: match.path, sessionNames: sessionNames)
                else {
                    snapshotsByPID[process.pid] = unassociatedSnapshot(process: process)
                    continue
                }

                assignedPaths.insert(log.sourcePath)
                cache(logPath: log.sourcePath, for: process)
                snapshotsByPID[process.pid] = displaySnapshot(process: process, log: log)
            }
        }

        return processes.compactMap { snapshotsByPID[$0.pid] }
    }

    private func directMatch(
        for process: ProcessSnapshot,
        sessionNames: [String: String],
        excluding assignedPaths: Set<String>
    ) -> (log: SessionLogSnapshot, path: String)? {
        for path in process.openFilePaths.sorted() where !assignedPaths.contains(path) {
            if let log = readLog(atPath: path, sessionNames: sessionNames) {
                return (log, path)
            }
        }
        return nil
    }

    private struct MetadataRecord {
        let path: String
        let metadata: SessionMetadata
    }

    private func scanMetadata(excluding assignedPaths: Set<String>) throws -> [MetadataRecord] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw SessionDirectoryError.notDirectory(sessionsDirectory.path)
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw SessionDirectoryError.cannotEnumerate(sessionsDirectory.path)
        }

        var records: [MetadataRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", !assignedPaths.contains(url.path) else { continue }
            guard let metadata = try? logReader.readMetadata(at: url),
                  metadata.isTopLevelInteractiveTUI
            else {
                continue
            }
            records.append(MetadataRecord(path: url.path, metadata: metadata))
        }
        if let enumerationError {
            throw enumerationError
        }
        return records.sorted { $0.path < $1.path }
    }

    private func fallbackMatch(
        for process: ProcessSnapshot,
        records: [MetadataRecord],
        excluding assignedPaths: Set<String>
    ) -> MetadataRecord? {
        guard let cwd = process.workingDirectory else { return nil }
        return records
            .filter { record in
                guard !assignedPaths.contains(record.path), record.metadata.workingDirectory == cwd else {
                    return false
                }
                let offset = record.metadata.timestamp.timeIntervalSince(process.startedAt)
                return offset >= 0 && offset <= 120
            }
            .min { lhs, rhs in
                let lhsOffset = lhs.metadata.timestamp.timeIntervalSince(process.startedAt)
                let rhsOffset = rhs.metadata.timestamp.timeIntervalSince(process.startedAt)
                if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
                return lhs.path < rhs.path
            }
    }

    private func readLog(
        atPath path: String,
        sessionNames: [String: String]
    ) -> SessionLogSnapshot? {
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return try? logReader.readSession(
            at: url,
            sessionNames: sessionNames,
            modifiedAt: modifiedAt,
            now: now()
        )
    }

    private func cache(logPath: String, for process: ProcessSnapshot) {
        cachedAssociationByPID[process.pid] = CachedAssociation(
            processStartedAt: process.startedAt,
            logPath: logPath
        )
    }

    private func displaySnapshot(
        process: ProcessSnapshot,
        log: SessionLogSnapshot
    ) -> SessionDisplaySnapshot {
        SessionDisplaySnapshot(
            pid: process.pid,
            sessionID: log.sessionID,
            activity: log.activity,
            taskDescription: log.taskDescription,
            displayTaskDescription: log.displayTaskDescription,
            workingDirectory: log.workingDirectory
        )
    }

    private func unassociatedSnapshot(process: ProcessSnapshot) -> SessionDisplaySnapshot {
        let workingDirectory = process.workingDirectory ?? "未知工作目录"
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
            workingDirectory: workingDirectory
        )
    }

    private func displayOrder(_ lhs: SessionDisplaySnapshot, _ rhs: SessionDisplaySnapshot) -> Bool {
        if lhs.activity != rhs.activity {
            return lhs.activity == .running
        }
        let comparison = lhs.taskDescription.localizedCaseInsensitiveCompare(rhs.taskDescription)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.pid < rhs.pid
    }
}

private enum SessionDirectoryError: LocalizedError {
    case notDirectory(String)
    case cannotEnumerate(String)

    var errorDescription: String? {
        switch self {
        case let .notDirectory(path):
            return "会话路径不是目录：\(path)"
        case let .cannotEnumerate(path):
            return "无法枚举会话目录：\(path)"
        }
    }
}
