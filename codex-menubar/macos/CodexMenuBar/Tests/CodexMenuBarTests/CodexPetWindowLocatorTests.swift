import CoreGraphics
import XCTest
@testable import CodexMenuBar

final class CodexPetWindowLocatorTests: XCTestCase {
    func testDiscoversUniqueStructuralClusterWithoutWindowNames() async throws {
        let windows = cluster()
        let locator = makeLocator(windows: windows)

        let discovered = await locator.discover()
        let result = try XCTUnwrap(discovered)

        XCTAssertEqual(result.anchorWindowID, 10)
        XCTAssertEqual(result.anchorFrame, windows[0].frame)
        XCTAssertEqual(result.processIdentifier, 42)
        XCTAssertEqual(result.appVersion, "26.721.41059")
        XCTAssertEqual(Set(result.trackedWindowIDs), Set([10, 11, 12]))
        XCTAssertEqual(result.obstacleFrames, [windows[2].frame])
    }

    func testDiscoversMeasuredCompactOnlyClusterFromCodex26721() async throws {
        let windows = [
            window(
                id: 1_481,
                x: 1_610,
                y: 820,
                width: 243,
                height: 253,
                layer: 2
            ),
            window(
                id: 1_244,
                x: 1_536,
                y: 885,
                width: 384,
                height: 123,
                layer: 3
            ),
            window(
                id: 1_482,
                x: 0,
                y: 1_080,
                width: 0,
                height: 0,
                layer: 3
            )
        ]

        let discovered = await makeLocator(windows: windows).discover()
        let result = try XCTUnwrap(discovered)

        XCTAssertEqual(result.anchorWindowID, 1_481)
        XCTAssertEqual(Set(result.trackedWindowIDs), Set([1_244, 1_481]))
        XCTAssertEqual(result.obstacleFrames, [windows[1].frame])
    }

    func testAnchorWithoutAdjacentLayerThreeValidationWindowIsRejected() async {
        let result = await makeLocator(
            windows: [window(id: 10)]
        ).discover()

        XCTAssertNil(result)
    }

    func testOptionalNamesCannotRescueInvalidGeometry() async {
        var windows = cluster(names: true)
        windows[0] = window(
            id: 10,
            width: 500,
            height: 500,
            layer: 2,
            name: "Codex Pet Mascot Effect"
        )

        let result = await makeLocator(windows: windows).discover()
        XCTAssertNil(result)
    }

    func testRejectsOrdinaryCodexWindowAndWrongBundleOrPID() async {
        let ordinary = [
            window(id: 1, width: 1_000, height: 700, layer: 0, name: "Codex")
        ]
        let ordinaryResult = await makeLocator(windows: ordinary).discover()
        XCTAssertNil(ordinaryResult)

        let wrongBundleResult = await makeLocator(
            windows: cluster(),
            applications: [
                CodexApplicationDescriptor(
                    processIdentifier: 42,
                    bundleIdentifier: "com.example.other",
                    version: "1"
                )
            ]
        ).discover()
        XCTAssertNil(wrongBundleResult)

        let foreignWindows = cluster().map {
            QuartzWindowDescriptor(
                id: $0.id,
                ownerPID: 99,
                frame: $0.frame,
                layer: $0.layer,
                alpha: $0.alpha,
                sharingState: $0.sharingState,
                isOnScreen: $0.isOnScreen,
                name: $0.name
            )
        }
        let foreignResult = await makeLocator(windows: foreignWindows).discover()
        XCTAssertNil(foreignResult)
    }

    func testAmbiguousClustersHideInsteadOfGuessing() async {
        let windows = cluster() + cluster(idOffset: 20, xOffset: 1_500)

        let result = await makeLocator(windows: windows).discover()
        XCTAssertNil(result)
    }

    func testRejectsTransparentUnsharedAndOffscreenAnchors() async {
        for anchor in [
            window(id: 10, alpha: 0, isOnScreen: true),
            window(id: 10, sharingState: 0, isOnScreen: true),
            window(id: 10, isOnScreen: false)
        ] {
            var windows = cluster()
            windows[0] = anchor
            let result = await makeLocator(windows: windows).discover()
            XCTAssertNil(result)
        }
    }

    func testTargetedRefreshRequiresTheTrackedAnchorAndValidCluster() async throws {
        let windows = cluster()
        let provider = FakeWindowMetadataProvider(
            applications: codexApplications(),
            visible: windows,
            targeted: windows
        )
        let locator = CodexPetWindowLocator(provider: provider)
        let discovered = await locator.discover()
        let original = try XCTUnwrap(discovered)

        let refreshResult = await locator.refresh(original)
        let refreshed = try XCTUnwrap(refreshResult)

        XCTAssertEqual(refreshed.anchorWindowID, original.anchorWindowID)
        XCTAssertEqual(refreshed.trackedWindowIDs, original.trackedWindowIDs)

        let missingAnchorProvider = FakeWindowMetadataProvider(
            applications: codexApplications(),
            visible: windows,
            targeted: Array(windows.dropFirst())
        )
        let missingAnchorLocator = CodexPetWindowLocator(
            provider: missingAnchorProvider
        )
        let missingResult = await missingAnchorLocator.refresh(original)
        XCTAssertNil(missingResult)
    }

    private func makeLocator(
        windows: [QuartzWindowDescriptor],
        applications: [CodexApplicationDescriptor]? = nil
    ) -> CodexPetWindowLocator {
        CodexPetWindowLocator(
            provider: FakeWindowMetadataProvider(
                applications: applications ?? codexApplications(),
                visible: windows,
                targeted: windows
            )
        )
    }

    private func codexApplications() -> [CodexApplicationDescriptor] {
        [
            CodexApplicationDescriptor(
                processIdentifier: 42,
                bundleIdentifier: "com.openai.codex",
                version: "26.721.41059"
            )
        ]
    }

    private func cluster(
        idOffset: CGWindowID = 0,
        xOffset: CGFloat = 0,
        names: Bool = false
    ) -> [QuartzWindowDescriptor] {
        [
            window(
                id: 10 + idOffset,
                x: 900 + xOffset,
                y: 500,
                width: 243,
                height: 253,
                layer: 2,
                name: names ? "Codex Pet Mascot Effect" : nil
            ),
            window(
                id: 11 + idOffset,
                x: 700 + xOffset,
                y: 350,
                width: 768,
                height: 912,
                layer: 3,
                name: names ? "Codex Pet Composition Surface" : nil
            ),
            window(
                id: 12 + idOffset,
                x: 830 + xOffset,
                y: 460,
                width: 345,
                height: 54,
                layer: 3,
                name: names ? "Codex Pet Activity Stack Backing" : nil
            )
        ]
    }

    private func window(
        id: CGWindowID,
        pid: pid_t = 42,
        x: CGFloat = 900,
        y: CGFloat = 500,
        width: CGFloat = 243,
        height: CGFloat = 253,
        layer: Int = 2,
        alpha: Double = 1,
        sharingState: Int = 1,
        isOnScreen: Bool = true,
        name: String? = nil
    ) -> QuartzWindowDescriptor {
        QuartzWindowDescriptor(
            id: id,
            ownerPID: pid,
            frame: CGRect(x: x, y: y, width: width, height: height),
            layer: layer,
            alpha: alpha,
            sharingState: sharingState,
            isOnScreen: isOnScreen,
            name: name
        )
    }
}

private struct FakeWindowMetadataProvider: CodexWindowMetadataProviding {
    let applications: [CodexApplicationDescriptor]
    let visible: [QuartzWindowDescriptor]
    let targeted: [QuartzWindowDescriptor]

    func runningApplications() async -> [CodexApplicationDescriptor] {
        applications
    }

    func visibleWindows() async -> [QuartzWindowDescriptor] {
        visible
    }

    func windows(withIDs ids: [CGWindowID]) async -> [QuartzWindowDescriptor] {
        let requested = Set(ids)
        return targeted.filter { requested.contains($0.id) }
    }
}
