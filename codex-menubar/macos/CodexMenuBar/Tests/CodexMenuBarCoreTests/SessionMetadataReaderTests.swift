import Foundation
import XCTest
@testable import CodexMenuBarCore

final class SessionMetadataReaderTests: XCTestCase {
    func testReadsOnlyFirstLineWithStrict256KiBLimit() throws {
        let metadata = #"{"type":"session_meta","payload":{"id":"session-1"}}"#
        let body = #"{"type":"event_msg","payload":{"type":"token_count"}}"#
        let prefixReader = RecordingPrefixReader(data: Data("\(metadata)\n\(body)\n".utf8))
        let reader = SessionMetadataReader(prefixReader: prefixReader)

        let record = try XCTUnwrap(reader.firstRecord(at: URL(fileURLWithPath: "/session.jsonl")))

        XCTAssertEqual(prefixReader.maximumByteCounts, [256 * 1_024])
        XCTAssertEqual(String(decoding: record.data, as: UTF8.self), metadata)
        XCTAssertFalse(record.data.contains(Data(body.utf8)))
        XCTAssertEqual(record.lineNumber, 1)
    }

    func testRejectsFirstLineThatDoesNotTerminateWithinLimit() {
        let prefixReader = RecordingPrefixReader(data: Data(repeating: 0x78, count: 256 * 1_024))
        let reader = SessionMetadataReader(prefixReader: prefixReader)

        XCTAssertNil(reader.firstRecord(at: URL(fileURLWithPath: "/oversized.jsonl")))
    }
}

private final class RecordingPrefixReader: FilePrefixReading, @unchecked Sendable {
    let data: Data
    private(set) var maximumByteCounts: [Int] = []

    init(data: Data) {
        self.data = data
    }

    func readPrefix(url: URL, maximumByteCount: Int) throws -> Data {
        maximumByteCounts.append(maximumByteCount)
        return Data(data.prefix(maximumByteCount))
    }
}
