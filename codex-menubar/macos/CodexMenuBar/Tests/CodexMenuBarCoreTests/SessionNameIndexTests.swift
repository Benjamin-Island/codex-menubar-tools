import Foundation
import XCTest
@testable import CodexMenuBarCore

final class SessionNameIndexTests: XCTestCase {
    private var root: URL!
    private var indexURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionNameIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        indexURL = root.appendingPathComponent("session_index.jsonl")
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testKeepsOnlyRequestedBoundedNamesAndRefreshesRename() throws {
        try write([
            name(id: "wanted", value: String(repeating: "x", count: 600)),
            name(id: "other", value: "Other")
        ])
        let index = SessionNameIndex(maximumNameCharacters: 512)

        var names = try index.names(at: indexURL, forSessionIDs: ["wanted"])
        XCTAssertEqual(names["wanted"]?.count, 512)
        XCTAssertNil(names["other"])

        try write([name(id: "wanted", value: "Renamed")], atomically: true)
        names = try index.names(at: indexURL, forSessionIDs: ["wanted"])
        XCTAssertEqual(names["wanted"], "Renamed")
    }

    func testMissingIndexAndMalformedLinesReturnNoNames() throws {
        let index = SessionNameIndex()
        XCTAssertEqual(try index.names(at: indexURL, forSessionIDs: ["wanted"]), [:])

        try write(["{malformed", name(id: "wanted", value: "   ")])
        XCTAssertEqual(try index.names(at: indexURL, forSessionIDs: ["wanted"]), [:])
    }

    private func write(_ records: [String], atomically: Bool = false) throws {
        try Data((records.joined(separator: "\n") + "\n").utf8)
            .write(to: indexURL, options: atomically ? .atomic : [])
    }

    private func name(id: String, value: String) -> String {
        #"{"id":"\#(id)","thread_name":"\#(value)"}"#
    }
}
