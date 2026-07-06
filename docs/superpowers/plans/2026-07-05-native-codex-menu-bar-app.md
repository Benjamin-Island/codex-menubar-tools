# Native Codex Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that reads local Codex session logs and displays remaining usage as a crisp, battery-sized status indicator without SwiftBar raster/base64 artifacts.

**Architecture:** Create a new Swift Package in `macos/CodexUsageMenuBar/` with a testable `CodexUsageCore` library and an AppKit executable target. The core library owns log discovery, JSON parsing, formatting, and refresh state; the app target owns `NSStatusItem`, menu rendering, timers, and the native status image renderer.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit, Foundation, XCTest, shell build script for `.app` bundle creation.

---

## File Structure

- Create `macos/CodexUsageMenuBar/Package.swift`: Swift Package with library target `CodexUsageCore`, executable target `CodexUsageMenuBar`, and XCTest target `CodexUsageCoreTests`.
- Create `macos/CodexUsageMenuBar/Sources/CodexUsageCore/UsageModels.swift`: usage data structs, errors, formatting helpers.
- Create `macos/CodexUsageMenuBar/Sources/CodexUsageCore/CodexLogReader.swift`: session file discovery and newest `token_count` event parsing.
- Create `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/main.swift`: AppKit entry point and app delegate.
- Create `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/StatusController.swift`: status item setup, refresh timer, menu content.
- Create `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/UsageIndicatorRenderer.swift`: native `NSImage` drawing for a filled, battery-sized template indicator.
- Create `macos/CodexUsageMenuBar/Tests/CodexUsageCoreTests/CodexLogReaderTests.swift`: parsing and discovery tests using temp directories.
- Create `macos/CodexUsageMenuBar/scripts/build-app.sh`: builds release binary and creates `CodexUsageMenuBar.app`.
- Modify `README.md`: document SwiftBar fallback and native app build/run workflow.

## Task 1: Swift Package And Core Log Parser

**Files:**
- Create: `macos/CodexUsageMenuBar/Package.swift`
- Create: `macos/CodexUsageMenuBar/Sources/CodexUsageCore/UsageModels.swift`
- Create: `macos/CodexUsageMenuBar/Sources/CodexUsageCore/CodexLogReader.swift`
- Create: `macos/CodexUsageMenuBar/Tests/CodexUsageCoreTests/CodexLogReaderTests.swift`

- [ ] **Step 1: Create package directories**

Run:

```bash
mkdir -p macos/CodexUsageMenuBar/Sources/CodexUsageCore
mkdir -p macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar
mkdir -p macos/CodexUsageMenuBar/Tests/CodexUsageCoreTests
```

Expected: directories exist and `git status --short` shows `?? macos/`.

- [ ] **Step 2: Add `Package.swift`**

Create `macos/CodexUsageMenuBar/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageMenuBar",
            dependencies: ["CodexUsageCore"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"]
        )
    ]
)
```

- [ ] **Step 3: Add core models and formatters**

Create `macos/CodexUsageMenuBar/Sources/CodexUsageCore/UsageModels.swift`:

```swift
import Foundation

public struct WindowUsage: Equatable, Sendable {
    public let label: String
    public let usedPercent: Double?
    public let remainingPercent: Int?
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double?, remainingPercent: Int?, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let primary: WindowUsage?
    public let secondary: WindowUsage?
    public let planType: String?
    public let creditsDescription: String?
    public let reportedAt: Date?
    public let sourcePath: String
}

public struct UsageReadError: Error, Equatable, Sendable {
    public let menuValue: String
    public let message: String
    public let detail: String?
}

public enum UsageReadResult: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case failure(UsageReadError)
}

public enum UsageFormatting {
    public static func remainingFromUsed(_ usedPercent: Double?) -> Int? {
        guard let usedPercent else { return nil }
        let remaining = 100.0 - usedPercent
        return Int(min(100.0, max(0.0, remaining)).rounded())
    }

    public static func windowLabel(minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let wholeMinutes = Int(minutes)
        if wholeMinutes % 1440 == 0 {
            return "\(wholeMinutes / 1440)d"
        }
        if wholeMinutes % 60 == 0 {
            return "\(wholeMinutes / 60)h"
        }
        return "\(wholeMinutes)m"
    }

    public static func menuLabel(_ remainingPercent: Int?) -> String {
        guard let remainingPercent else { return "--" }
        return "\(min(100, max(0, remainingPercent)))"
    }

    public static func percentLabel(_ remainingPercent: Int?) -> String {
        guard let remainingPercent else { return "--" }
        return "\(remainingPercent)%"
    }

    public static func dateLabel(_ date: Date?, calendar: Calendar = .current, now: Date = Date()) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm:ss"
        } else {
            formatter.dateFormat = "MMM d HH:mm"
        }
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Add log reader**

Create `macos/CodexUsageMenuBar/Sources/CodexUsageCore/CodexLogReader.swift`:

```swift
import Foundation

public final class CodexLogReader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func readLatestSnapshot(sessionsDirectory: URL) -> UsageReadResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(UsageReadError(
                menuValue: "--",
                message: "No Codex session directory found",
                detail: sessionsDirectory.path
            ))
        }

        let files: [URL]
        do {
            files = try discoverSessionFiles(in: sessionsDirectory)
        } catch {
            return .failure(UsageReadError(
                menuValue: "!",
                message: "Unable to read Codex session logs",
                detail: "\(type(of: error)): \(error.localizedDescription)"
            ))
        }

        var firstReadError: String?
        for file in files {
            do {
                if let snapshot = try readLatestSnapshot(from: file) {
                    return .snapshot(snapshot)
                }
            } catch {
                if firstReadError == nil {
                    firstReadError = "\(file.path): \(type(of: error)): \(error.localizedDescription)"
                }
            }
        }

        if let firstReadError {
            return .failure(UsageReadError(
                menuValue: "!",
                message: "Unable to read Codex session logs",
                detail: firstReadError
            ))
        }

        return .failure(UsageReadError(
            menuValue: "--",
            message: "No rate limit event found yet. Open or use Codex once to generate usage data.",
            detail: nil
        ))
    }

    public func discoverSessionFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [(Date, URL)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            candidates.append((values.contentModificationDate ?? .distantPast, fileURL))
        }
        return candidates.sorted { $0.0 > $1.0 }.map(\.1)
    }

    public func readLatestSnapshot(from fileURL: URL) throws -> UsageSnapshot? {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            if let snapshot = makeSnapshot(from: record, sourcePath: fileURL.path) {
                return snapshot
            }
        }
        return nil
    }

    private func makeSnapshot(from record: SessionRecord, sourcePath: String) -> UsageSnapshot? {
        guard record.type == "event_msg",
              record.payload.type == "token_count",
              let rateLimits = record.payload.rateLimits
        else {
            return nil
        }

        let primary = makeWindow(rateLimits.primary)
        let secondary = makeWindow(rateLimits.secondary)
        guard primary != nil || secondary != nil else { return nil }

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: rateLimits.planType,
            creditsDescription: creditsDescription(rateLimits.credits),
            reportedAt: parseTimestamp(record.timestamp),
            sourcePath: sourcePath
        )
    }

    private func makeWindow(_ raw: RateLimitWindow?) -> WindowUsage? {
        guard let raw else { return nil }
        return WindowUsage(
            label: UsageFormatting.windowLabel(minutes: raw.windowMinutes),
            usedPercent: raw.usedPercent,
            remainingPercent: UsageFormatting.remainingFromUsed(raw.usedPercent),
            resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func creditsDescription(_ credits: Credits?) -> String? {
        guard let credits else { return nil }
        if credits.unlimited == true { return "unlimited" }
        if let balance = credits.balance { return "\(balance)" }
        if credits.hasCredits == false { return "none" }
        if credits.hasCredits == true { return "available" }
        return nil
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct SessionRecord: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload
}

private struct Payload: Decodable {
    let type: String?
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: Credits?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private struct Credits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Int?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
```

- [ ] **Step 5: Add core tests**

Create `macos/CodexUsageMenuBar/Tests/CodexUsageCoreTests/CodexLogReaderTests.swift` with tests for:

```swift
import XCTest
@testable import CodexUsageCore

final class CodexLogReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var reader: CodexLogReader!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMenuBarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        reader = CodexLogReader()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsPrimaryAndSecondaryRemaining() throws {
        let session = tempDirectory.appendingPathComponent("2026/07/05/session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 12, usedSecondary: 4)], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.label, "5h")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 88)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 96)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.creditsDescription, "none")
    }

    func testSkipsBadJsonAndUsesOlderValidEvent() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 45, usedSecondary: 10), "{bad json"], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.remainingPercent, 55)
    }

    func testMissingSessionsDirectoryReturnsFailure() {
        let missing = tempDirectory.appendingPathComponent("missing")

        let result = reader.readLatestSnapshot(sessionsDirectory: missing)

        XCTAssertEqual(result, .failure(UsageReadError(
            menuValue: "--",
            message: "No Codex session directory found",
            detail: missing.path
        )))
    }

    func testNoRateLimitEventReturnsFailure() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [#"{"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .failure(error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error.menuValue, "--")
        XCTAssertTrue(error.message.contains("No rate limit event"))
    }

    private func write(records: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try records.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func tokenCountEvent(usedPrimary: Int, usedSecondary: Int) -> String {
        """
        {"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\(usedPrimary),"window_minutes":300,"resets_at":1783070400},"secondary":{"used_percent":\(usedSecondary),"window_minutes":10080,"resets_at":1783630800},"credits":{"has_credits":false,"unlimited":false,"balance":null},"plan_type":"plus"}}}
        """
    }
}
```

- [ ] **Step 6: Verify tests**

Run:

```bash
cd macos/CodexUsageMenuBar
swift test
```

Expected: all `CodexUsageCoreTests` pass.

- [ ] **Step 7: Commit**

```bash
git add macos/CodexUsageMenuBar
git commit -m "Add native menu bar core parser"
```

## Task 2: Native AppKit Menu Bar UI

**Files:**
- Create: `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/main.swift`
- Create: `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/StatusController.swift`
- Create: `macos/CodexUsageMenuBar/Sources/CodexUsageMenuBar/UsageIndicatorRenderer.swift`

- [ ] **Step 1: Add AppKit entry point**

Create `main.swift`:

```swift
import AppKit
import CodexUsageCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sessionsDirectory = ProcessInfo.processInfo.environment["CODEX_SESSIONS_DIR"]
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex")
                .appendingPathComponent("sessions")

        statusController = StatusController(
            sessionsDirectory: sessionsDirectory,
            reader: CodexLogReader(),
            refreshInterval: 30
        )
        statusController?.start()
    }
}
```

- [ ] **Step 2: Add native status image renderer**

Create `UsageIndicatorRenderer.swift`:

```swift
import AppKit

struct UsageIndicatorRenderer {
    static let imageSize = NSSize(width: 34, height: 14)

    func image(label: String, progress: Double?) -> NSImage {
        let image = NSImage(size: Self.imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.isTemplate = true
            return image
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.clear(CGRect(origin: .zero, size: Self.imageSize))

        let rect = CGRect(x: 0.5, y: 0.5, width: Self.imageSize.width - 1, height: Self.imageSize.height - 1)
        let radius = rect.height / 2
        let outerPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.addPath(outerPath)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.42).cgColor)
        context.fillPath()

        if let progress {
            let innerRect = rect.insetBy(dx: 1.8, dy: 2.0)
            let progressWidth = max(1.0, innerRect.width * min(1.0, max(0.0, progress)))
            let progressRect = CGRect(x: innerRect.minX, y: innerRect.minY, width: progressWidth, height: innerRect.height)

            context.addPath(CGPath(
                roundedRect: progressRect,
                cornerWidth: innerRect.height / 2,
                cornerHeight: innerRect.height / 2,
                transform: nil
            ))
            context.setFillColor(NSColor.labelColor.withAlphaComponent(0.96).cgColor)
            context.fillPath()
        }

        let text = label as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: paragraph
        ]

        context.saveGState()
        context.setBlendMode(.clear)
        text.draw(in: CGRect(x: 0, y: 1.0, width: Self.imageSize.width, height: Self.imageSize.height), withAttributes: attributes)
        context.restoreGState()

        image.isTemplate = true
        return image
    }
}
```

- [ ] **Step 3: Add status controller**

Create `StatusController.swift`:

```swift
import AppKit
import CodexUsageCore

@MainActor
final class StatusController {
    private let statusItem: NSStatusItem
    private let sessionsDirectory: URL
    private let reader: CodexLogReader
    private let renderer: UsageIndicatorRenderer
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var lastResult: UsageReadResult?

    init(
        sessionsDirectory: URL,
        reader: CodexLogReader,
        renderer: UsageIndicatorRenderer = UsageIndicatorRenderer(),
        refreshInterval: TimeInterval
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.reader = reader
        self.renderer = renderer
        self.refreshInterval = refreshInterval
        self.statusItem = NSStatusBar.system.statusItem(withLength: UsageIndicatorRenderer.imageSize.width)
    }

    func start() {
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        let result = reader.readLatestSnapshot(sessionsDirectory: sessionsDirectory)
        lastResult = result

        let remaining: Int?
        let label: String
        switch result {
        case .snapshot(let snapshot):
            remaining = snapshot.primary?.remainingPercent
            label = UsageFormatting.menuLabel(remaining)
        case .failure(let error):
            remaining = nil
            label = error.menuValue
        }

        statusItem.button?.image = renderer.image(
            label: label,
            progress: remaining.map { Double($0) / 100.0 }
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Codex usage \(label)"
        configureMenu()
    }

    private func configureMenu() {
        let menu = NSMenu()
        switch lastResult {
        case .snapshot(let snapshot):
            menu.addItem(NSMenuItem(title: "Codex usage", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            addWindowItems(to: menu, prefix: "Primary", window: snapshot.primary)
            addWindowItems(to: menu, prefix: "Secondary", window: snapshot.secondary)
            menu.addItem(NSMenuItem(title: "Plan: \(snapshot.planType ?? "--")", action: nil, keyEquivalent: ""))
            if let credits = snapshot.creditsDescription {
                menu.addItem(NSMenuItem(title: "Credits: \(credits)", action: nil, keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Last reported: \(UsageFormatting.dateLabel(snapshot.reportedAt))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Source: local Codex session logs", action: nil, keyEquivalent: ""))
        case .failure(let error):
            menu.addItem(NSMenuItem(title: error.message, action: nil, keyEquivalent: ""))
            if let detail = error.detail {
                menu.addItem(NSMenuItem(title: "Detail: \(detail)", action: nil, keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Source: local Codex session logs", action: nil, keyEquivalent: ""))
        case nil:
            menu.addItem(NSMenuItem(title: "Loading Codex usage", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func addWindowItems(to menu: NSMenu, prefix: String, window: WindowUsage?) {
        guard let window else {
            menu.addItem(NSMenuItem(title: "\(prefix) remaining: --", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "\(prefix) resets: --", action: nil, keyEquivalent: ""))
            return
        }
        menu.addItem(NSMenuItem(title: "\(window.label) remaining: \(UsageFormatting.percentLabel(window.remainingPercent))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(window.label) resets: \(UsageFormatting.dateLabel(window.resetsAt))", action: nil, keyEquivalent: ""))
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 4: Verify build**

Run:

```bash
cd macos/CodexUsageMenuBar
swift build
swift test
```

Expected: build succeeds and tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos/CodexUsageMenuBar
git commit -m "Add native menu bar AppKit UI"
```

## Task 3: App Bundle Build Script And Documentation

**Files:**
- Create: `macos/CodexUsageMenuBar/scripts/build-app.sh`
- Modify: `README.md`

- [ ] **Step 1: Add build script**

Create `macos/CodexUsageMenuBar/scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexUsageMenuBar"
APP_DIR="$ROOT_DIR/.build/release/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageMenuBar</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex-usage-menubar</string>
  <key>CFBundleName</key>
  <string>Codex Usage Menu Bar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
```

Then run:

```bash
chmod +x macos/CodexUsageMenuBar/scripts/build-app.sh
```

- [ ] **Step 2: Update README**

Add a "Native macOS App" section before the SwiftBar install section:

```markdown
## Native macOS App

The native app is the preferred UI when you want the menu bar item to match macOS status icons. It renders the indicator through AppKit instead of sending a raster image through SwiftBar.

Build and test:

```bash
cd macos/CodexUsageMenuBar
swift test
swift build
```

Build an app bundle:

```bash
macos/CodexUsageMenuBar/scripts/build-app.sh
```

Run the generated app:

```bash
open macos/CodexUsageMenuBar/.build/release/CodexUsageMenuBar.app
```

For testing against a fixture directory:

```bash
CODEX_SESSIONS_DIR=/path/to/sessions swift run CodexUsageMenuBar
```

The app reads `~/.codex/sessions/**/*.jsonl`, creates a menu bar-only status item, refreshes every 30 seconds, and does not read auth files or make network requests.
```

- [ ] **Step 3: Verify app bundle build**

Run:

```bash
macos/CodexUsageMenuBar/scripts/build-app.sh
test -x macos/CodexUsageMenuBar/.build/release/CodexUsageMenuBar.app/Contents/MacOS/CodexUsageMenuBar
```

Expected: script prints the `.app` path and executable exists.

- [ ] **Step 4: Run full repository verification**

Run:

```bash
python -m unittest discover -s tests -p 'test_*.py'
cd macos/CodexUsageMenuBar && swift test
```

Expected: Python SwiftBar fallback tests pass and Swift native app tests pass.

- [ ] **Step 5: Commit**

```bash
git add README.md macos/CodexUsageMenuBar/scripts/build-app.sh
git commit -m "Document native menu bar app"
```

## Final Verification

Run:

```bash
python -m unittest discover -s tests -p 'test_*.py'
cd macos/CodexUsageMenuBar && swift test
cd macos/CodexUsageMenuBar && swift build
macos/CodexUsageMenuBar/scripts/build-app.sh
git status --short --branch
```

Expected: all tests and builds pass; generated app bundle exists under `.build/release/CodexUsageMenuBar.app`; git status is clean except ignored build outputs.

## Self-Review

- Spec coverage: plan covers native app folder, local Codex log parsing, crisp native status rendering, dropdown details, refresh, docs, tests, and app bundle creation.
- Placeholder scan: no TODO/TBD placeholders remain.
- Type consistency: `UsageSnapshot`, `WindowUsage`, `UsageFormatting`, `CodexLogReader`, `StatusController`, and `UsageIndicatorRenderer` names are used consistently across tasks.
