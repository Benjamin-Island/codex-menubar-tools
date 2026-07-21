import Foundation
import Darwin

final class SessionNameIndex: @unchecked Sendable {
    private let rangeReader: any FileRangeReading
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private let maximumNameCharacters: Int
    private let lock = NSLock()
    private var cachedFingerprint: LogFileFingerprint?
    private var cachedNames: [String: String] = [:]
    private var scannedSessionIDs: Set<String> = []

    init(
        rangeReader: any FileRangeReading = FileHandleRangeReader(),
        chunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 8 * 1_024 * 1_024,
        maximumNameCharacters: Int = 512
    ) {
        precondition(chunkSize > 0)
        precondition(maximumLineBytes > 0)
        precondition(maximumNameCharacters > 0)
        self.rangeReader = rangeReader
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
        self.maximumNameCharacters = maximumNameCharacters
    }

    func names(at indexURL: URL, forSessionIDs requestedIDs: Set<String>) throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        guard !requestedIDs.isEmpty else {
            cachedNames = [:]
            scannedSessionIDs = []
            return [:]
        }
        guard let fingerprint = try fingerprint(at: indexURL) else {
            cachedFingerprint = nil
            cachedNames = [:]
            scannedSessionIDs = requestedIDs
            return [:]
        }

        if cachedFingerprint == fingerprint, requestedIDs.isSubset(of: scannedSessionIDs) {
            return cachedNames.filter { requestedIDs.contains($0.key) }
        }

        var framing = JSONLFramingState(maximumLineBytes: maximumLineBytes)
        var nextNames: [String: String] = [:]
        try rangeReader.read(
            url: indexURL,
            range: 0..<UInt64(max(0, fingerprint.byteSize)),
            chunkSize: chunkSize
        ) { data in
            let output = framing.consume(data, path: indexURL.path)
            for record in output.records {
                guard let object = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any],
                      let id = object["id"] as? String,
                      requestedIDs.contains(id),
                      let rawName = object["thread_name"] as? String
                else { continue }
                let normalized = SessionTextFormatting.normalized(rawName)
                if !normalized.isEmpty {
                    nextNames[id] = String(normalized.prefix(maximumNameCharacters))
                }
            }
        }

        cachedFingerprint = fingerprint
        cachedNames = nextNames
        scannedSessionIDs = requestedIDs
        return nextNames
    }

    private func fingerprint(at url: URL) throws -> LogFileFingerprint? {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }

        var fileStat = stat()
        let result = path.withCString { lstat($0, &fileStat) }
        guard result == 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return LogFileFingerprint(
            path: path,
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            byteSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            identity: LogFileIdentity(
                device: UInt64(fileStat.st_dev),
                inode: UInt64(fileStat.st_ino)
            )
        )
    }
}
