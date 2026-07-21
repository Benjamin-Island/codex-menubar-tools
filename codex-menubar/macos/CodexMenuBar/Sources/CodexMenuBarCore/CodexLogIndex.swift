import Foundation
import Darwin

public struct LogFileIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    public static let unknown = LogFileIdentity(device: 0, inode: 0)
}

public struct LogFileFingerprint: Hashable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let byteSize: Int64
    public let identity: LogFileIdentity

    public init(
        path: String,
        modifiedAt: Date,
        byteSize: Int64,
        identity: LogFileIdentity = .unknown
    ) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.modifiedAt = modifiedAt
        self.byteSize = byteSize
        self.identity = identity
    }
}

public struct LogIndexSnapshot: Equatable, Sendable {
    public let logs: [IndexedSessionLog]
    public let warnings: [ParseWarning]

    public init(logs: [IndexedSessionLog], warnings: [ParseWarning]) {
        self.logs = logs
        self.warnings = warnings
    }
}

public protocol LogParsing: Sendable {
    func parse(
        logURL: URL,
        sessionNames: [String: String],
        modifiedAt: Date
    ) throws -> IndexedSessionLog
    func readSessionNames(at indexURL: URL) throws -> [String: String]
}

public protocol LogFileDiscovering: Sendable {
    func discovery(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> LogDiscoverySnapshot
}

public struct LogDiscoverySnapshot: Equatable, Sendable {
    public let fingerprints: [LogFileFingerprint]
    public let omittedFileCount: Int

    public init(fingerprints: [LogFileFingerprint], omittedFileCount: Int) {
        self.fingerprints = fingerprints
        self.omittedFileCount = omittedFileCount
    }
}

enum LogFingerprintSelection {
    static func select(
        _ input: [LogFileFingerprint],
        requiredPaths: Set<String>,
        ordinaryLimit: Int
    ) -> LogDiscoverySnapshot {
        precondition(ordinaryLimit >= 0)
        let required = Set(requiredPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        let requiredFiles = input.filter { required.contains($0.path) }
        let ordinary = input.filter { !required.contains($0.path) }.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.path < $1.path
        }
        let kept = Array(ordinary.prefix(ordinaryLimit)) + requiredFiles
        return LogDiscoverySnapshot(
            fingerprints: kept.sorted { $0.path < $1.path },
            omittedFileCount: max(0, ordinary.count - ordinaryLimit)
        )
    }
}

extension CodexLogParser: LogParsing {}

public enum LogDiscoveryError: Error, Equatable, Sendable {
    case missingDirectory(String)
    case notDirectory(String)
    case cannotEnumerate(String)
    case cannotRead(String)
}

public struct FileSystemLogDiscoverer: LogFileDiscovering, @unchecked Sendable {
    private let fileManager: FileManager
    private let ordinaryLimit: Int

    public init(fileManager: FileManager = .default, ordinaryLimit: Int = 10_000) {
        precondition(ordinaryLimit >= 0)
        self.fileManager = fileManager
        self.ordinaryLimit = ordinaryLimit
    }

    public func discovery(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> LogDiscoverySnapshot {
        let directory = sessionsDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            throw LogDiscoveryError.missingDirectory(directory.path)
        }
        guard isDirectory.boolValue else {
            throw LogDiscoveryError.notDirectory(directory.path)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw LogDiscoveryError.cannotEnumerate(directory.path)
        }

        let required = Set(requiredPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        var urlsByPath: [String: URL] = [:]
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urlsByPath[url.standardizedFileURL.path] = url.standardizedFileURL
        }
        if enumerationError != nil {
            throw LogDiscoveryError.cannotRead(directory.path)
        }
        for path in required where fileManager.fileExists(atPath: path) {
            urlsByPath[path] = URL(fileURLWithPath: path).standardizedFileURL
        }

        let fingerprints: [LogFileFingerprint] = try urlsByPath.values.compactMap { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { return nil }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard modifiedAt >= modifiedSince || required.contains(url.path) else { return nil }
            return LogFileFingerprint(
                path: url.path,
                modifiedAt: modifiedAt,
                byteSize: Int64(values.fileSize ?? 0),
                identity: try fileIdentity(path: url.path)
            )
        }
        return LogFingerprintSelection.select(
            fingerprints,
            requiredPaths: required,
            ordinaryLimit: ordinaryLimit
        )
    }

    private func fileIdentity(path: String) throws -> LogFileIdentity {
        var fileStat = stat()
        let result = path.withCString { lstat($0, &fileStat) }
        guard result == 0 else { throw LogDiscoveryError.cannotRead(path) }
        return LogFileIdentity(
            device: UInt64(fileStat.st_dev),
            inode: UInt64(fileStat.st_ino)
        )
    }
}

public final class CodexLogIndex: @unchecked Sendable {
    private struct Entry {
        let fingerprint: LogFileFingerprint
        let log: IndexedSessionLog
    }

    private let parser: any LogParsing
    private let discoverer: any LogFileDiscovering
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(
        parser: any LogParsing = CodexLogParser(),
        discoverer: any LogFileDiscovering = FileSystemLogDiscoverer()
    ) {
        self.parser = parser
        self.discoverer = discoverer
    }

    public func refresh(
        sessionsDirectory: URL,
        sessionIndexURL: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> LogIndexSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let sessionNames = try parser.readSessionNames(at: sessionIndexURL)
        let discovery = try discoverer.discovery(
            in: sessionsDirectory,
            modifiedSince: modifiedSince,
            requiredPaths: requiredPaths
        )
        let fingerprints = discovery.fingerprints

        var nextEntries: [String: Entry] = [:]
        var refreshWarnings: [ParseWarning] = []
        for fingerprint in fingerprints.sorted(by: { $0.path < $1.path }) {
            if let existing = entries[fingerprint.path], existing.fingerprint == fingerprint {
                nextEntries[fingerprint.path] = existing
                continue
            }

            do {
                let log = try parser.parse(
                    logURL: URL(fileURLWithPath: fingerprint.path),
                    sessionNames: sessionNames,
                    modifiedAt: fingerprint.modifiedAt
                )
                nextEntries[fingerprint.path] = Entry(fingerprint: fingerprint, log: log)
            } catch {
                refreshWarnings.append(ParseWarning(
                    path: fingerprint.path,
                    line: 0,
                    message: "Unable to read log: \(error.localizedDescription)"
                ))
                if let existing = entries[fingerprint.path] {
                    nextEntries[fingerprint.path] = existing
                }
            }
        }

        entries = nextEntries
        let logs = entries.values.map(\.log).sorted { $0.path < $1.path }
        return LogIndexSnapshot(
            logs: logs,
            warnings: logs.flatMap(\.warnings) + refreshWarnings
        )
    }
}
