import Foundation

protocol FilePrefixReading: Sendable {
    func readPrefix(url: URL, maximumByteCount: Int) throws -> Data
}

struct FileHandlePrefixReader: FilePrefixReading, Sendable {
    func readPrefix(url: URL, maximumByteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var prefix = Data()
        while prefix.count < maximumByteCount {
            let requested = min(4 * 1_024, maximumByteCount - prefix.count)
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                break
            }
            prefix.append(chunk)
            if let newline = prefix.firstIndex(of: 0x0A) {
                return Data(prefix[...newline])
            }
        }
        return prefix
    }
}

struct SessionMetadataReader: Sendable {
    static let maximumByteCount = 256 * 1_024

    private let prefixReader: any FilePrefixReading

    init(prefixReader: any FilePrefixReading = FileHandlePrefixReader()) {
        self.prefixReader = prefixReader
    }

    func firstRecord(at url: URL) -> JSONLRecord? {
        guard let prefix = try? prefixReader.readPrefix(
            url: url,
            maximumByteCount: Self.maximumByteCount
        ),
        let newline = prefix.firstIndex(of: 0x0A)
        else {
            return nil
        }
        var line = Data(prefix[..<newline])
        if line.last == 0x0D {
            line.removeLast()
        }
        guard !line.isEmpty else { return nil }
        return JSONLRecord(data: line, lineNumber: 1)
    }
}
