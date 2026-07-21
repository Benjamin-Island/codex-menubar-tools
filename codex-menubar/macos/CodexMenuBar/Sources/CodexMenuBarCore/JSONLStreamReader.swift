import Foundation

enum JSONLReadError: Error, Equatable {
    case invalidChunkSize(Int)
    case unexpectedEndOfFile(String)
}

protocol FileRangeReading: Sendable {
    func read(
        url: URL,
        range: Range<UInt64>,
        chunkSize: Int,
        consume: (Data) throws -> Void
    ) throws
}

struct FileHandleRangeReader: FileRangeReading, Sendable {
    func read(
        url: URL,
        range: Range<UInt64>,
        chunkSize: Int,
        consume: (Data) throws -> Void
    ) throws {
        guard chunkSize > 0 else { throw JSONLReadError.invalidChunkSize(chunkSize) }
        guard !range.isEmpty else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: range.lowerBound)

        var remaining = range.upperBound - range.lowerBound
        while remaining > 0 {
            let requested = Int(min(UInt64(chunkSize), remaining))
            guard let data = try handle.read(upToCount: requested), !data.isEmpty else {
                throw JSONLReadError.unexpectedEndOfFile(url.path)
            }
            try consume(data)
            remaining -= UInt64(data.count)
        }
    }
}

struct JSONLRecord: Equatable, Sendable {
    let data: Data
    let lineNumber: Int
}

struct JSONLFrameOutput: Equatable, Sendable {
    let records: [JSONLRecord]
    let warnings: [ParseWarning]
}

struct JSONLFramingState: Equatable, Sendable {
    private var pending = Data()
    private var isSkippingOversizedLine = false
    private var nextLineNumber = 1
    private let maximumLineBytes: Int

    var pendingByteCount: Int { pending.count }

    init(maximumLineBytes: Int) {
        precondition(maximumLineBytes > 0)
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func consume(_ data: Data, path: String) -> JSONLFrameOutput {
        var records: [JSONLRecord] = []
        var warnings: [ParseWarning] = []

        for byte in data {
            if isSkippingOversizedLine {
                if byte == 0x0A {
                    isSkippingOversizedLine = false
                    nextLineNumber += 1
                }
                continue
            }

            if byte == 0x0A {
                if pending.last == 0x0D {
                    pending.removeLast()
                }
                if !pending.isEmpty {
                    records.append(JSONLRecord(data: pending, lineNumber: nextLineNumber))
                }
                pending.removeAll(keepingCapacity: true)
                nextLineNumber += 1
                continue
            }

            if pending.count == maximumLineBytes {
                pending.removeAll(keepingCapacity: true)
                isSkippingOversizedLine = true
                warnings.append(ParseWarning(
                    path: path,
                    line: nextLineNumber,
                    message: "JSONL line exceeds the \(maximumLineBytes)-byte safety limit."
                ))
                continue
            }

            pending.append(byte)
        }

        return JSONLFrameOutput(records: records, warnings: warnings)
    }
}
