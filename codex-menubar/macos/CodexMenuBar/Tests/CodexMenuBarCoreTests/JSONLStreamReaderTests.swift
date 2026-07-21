import Foundation
import XCTest
@testable import CodexMenuBarCore

final class JSONLStreamReaderTests: XCTestCase {
    func testFileRangeReaderReadsOnlyRequestedBytes() throws {
        let url = try temporaryFile(Data("zero\none\ntwo\n".utf8))
        var output = Data()

        try FileHandleRangeReader().read(url: url, range: 5..<9, chunkSize: 2) {
            output.append($0)
        }

        XCTAssertEqual(String(decoding: output, as: UTF8.self), "one\n")
    }

    func testFileRangeReaderRejectsUnexpectedEndOfFile() throws {
        let url = try temporaryFile(Data("short".utf8))

        XCTAssertThrowsError(
            try FileHandleRangeReader().read(url: url, range: 0..<10, chunkSize: 3) { _ in }
        ) { error in
            guard case JSONLReadError.unexpectedEndOfFile(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, url.path)
        }
    }

    func testFramerCarriesIncompleteLineAndEmitsItOnce() {
        var state = JSONLFramingState(maximumLineBytes: 1_024)

        XCTAssertTrue(
            state.consume(Data(#"{"type":"token""#.utf8), path: "/a.jsonl").records.isEmpty
        )
        let output = state.consume(Data("}\n".utf8), path: "/a.jsonl")

        XCTAssertEqual(output.records.map(\.lineNumber), [1])
        XCTAssertEqual(String(decoding: output.records[0].data, as: UTF8.self), #"{"type":"token"}"#)
        XCTAssertEqual(state.pendingByteCount, 0)
    }

    func testFramerIgnoresEmptyLinesAndHandlesCRLF() {
        var state = JSONLFramingState(maximumLineBytes: 1_024)

        let output = state.consume(Data("\n{}\r\n\n".utf8), path: "/a.jsonl")

        XCTAssertEqual(output.records.map(\.lineNumber), [2])
        XCTAssertEqual(String(decoding: output.records[0].data, as: UTF8.self), "{}")
    }

    func testOversizedLineStaysBoundedAndResumes() {
        var state = JSONLFramingState(maximumLineBytes: 8)

        let oversized = state.consume(Data("123456789012".utf8), path: "/a.jsonl")
        XCTAssertLessThanOrEqual(state.pendingByteCount, 8)
        XCTAssertEqual(oversized.warnings.count, 1)

        let output = state.consume(Data("\n{}\n".utf8), path: "/a.jsonl")
        XCTAssertEqual(output.records.count, 1)
        XCTAssertEqual(output.records.first?.lineNumber, 2)
        XCTAssertTrue(output.warnings.isEmpty)
    }

    func testOversizedCustomToolCallOutputIsSilentlySkipped() {
        var state = JSONLFramingState(maximumLineBytes: 96)
        let prefix = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","output":""#
        let line = prefix + String(repeating: "x", count: 128) + #""}}"# + "\n{}\n"

        let output = state.consume(Data(line.utf8), path: "/tool-output.jsonl")

        XCTAssertTrue(output.warnings.isEmpty)
        XCTAssertEqual(output.records.map(\.lineNumber), [2])
        XCTAssertEqual(String(decoding: output.records[0].data, as: UTF8.self), "{}")
        XCTAssertLessThanOrEqual(state.pendingByteCount, 96)
    }

    func testOversizedTokenCountRecordStillWarns() {
        var state = JSONLFramingState(maximumLineBytes: 80)
        let prefix = #"{"type":"event_msg","payload":{"type":"token_count","info":""#
        let line = prefix + String(repeating: "x", count: 128) + #""}}"# + "\n"

        let output = state.consume(Data(line.utf8), path: "/token-count.jsonl")

        XCTAssertEqual(output.warnings, [ParseWarning(
            path: "/token-count.jsonl",
            line: 1,
            message: "JSONL line exceeds the 80-byte safety limit."
        )])
        XCTAssertLessThanOrEqual(state.pendingByteCount, 80)
    }

    func testToolMarkersInsideOversizedTokenContentDoNotSuppressWarning() {
        var state = JSONLFramingState(maximumLineBytes: 1_200)
        let prefix = #"{"type":"event_msg","payload":{"type":"token_count","info":""#
        let misleadingContent = String(repeating: "x", count: 1_050)
            + #""type":"response_item","type":"custom_tool_call_output""#
        let line = prefix + misleadingContent + String(repeating: "x", count: 128) + #""}}"# + "\n"

        let output = state.consume(Data(line.utf8), path: "/token-content.jsonl")

        XCTAssertEqual(output.warnings.count, 1)
        XCTAssertEqual(output.warnings.first?.line, 1)
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-stream-\(UUID().uuidString)")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
