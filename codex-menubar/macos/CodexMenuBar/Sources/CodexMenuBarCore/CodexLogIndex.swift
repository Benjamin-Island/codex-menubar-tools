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
    func fingerprints(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> [LogFileFingerprint]
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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fingerprints(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> [LogFileFingerprint] {
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

        return try urlsByPath.values.compactMap { url in
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
        }.sorted { $0.path < $1.path }
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
        let fingerprints = try discoverer.fingerprints(
            in: sessionsDirectory,
            modifiedSince: modifiedSince,
            requiredPaths: requiredPaths
        )

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
