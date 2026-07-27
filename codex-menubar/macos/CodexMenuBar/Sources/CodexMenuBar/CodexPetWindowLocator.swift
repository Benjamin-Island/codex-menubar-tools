import AppKit
import CoreGraphics
import Foundation

struct QuartzWindowDescriptor: Equatable, Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let sharingState: Int
    let isOnScreen: Bool
    let name: String?
}

struct CodexApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let version: String?
}

struct PetWindowObservation: Equatable, Sendable {
    let anchorWindowID: CGWindowID
    let trackedWindowIDs: [CGWindowID]
    let anchorFrame: CGRect
    let obstacleFrames: [CGRect]
    let processIdentifier: pid_t
    let appVersion: String?
}

protocol CodexWindowMetadataProviding: Sendable {
    func runningApplications() async -> [CodexApplicationDescriptor]
    func visibleWindows() async -> [QuartzWindowDescriptor]
    func windows(withIDs ids: [CGWindowID]) async -> [QuartzWindowDescriptor]
}

struct PetWindowMatchProfile: Equatable, Sendable {
    let anchorLayer: Int
    let anchorWidthRange: ClosedRange<CGFloat>
    let anchorHeightRange: ClosedRange<CGFloat>
    let validatingLayer: Int
    let compositionWidthRange: ClosedRange<CGFloat>
    let compositionHeightRange: ClosedRange<CGFloat>
    let compactWidthRange: ClosedRange<CGFloat>
    let compactHeightRange: ClosedRange<CGFloat>
    let maximumAdjacencyDistance: CGFloat

    static let codex26_721 = PetWindowMatchProfile(
        anchorLayer: 2,
        anchorWidthRange: 180 ... 300,
        anchorHeightRange: 180 ... 320,
        validatingLayer: 3,
        compositionWidthRange: 600 ... 950,
        compositionHeightRange: 700 ... 1_200,
        compactWidthRange: 20 ... 450,
        compactHeightRange: 20 ... 180,
        maximumAdjacencyDistance: 100
    )
}

final class SystemCodexWindowMetadataProvider:
    CodexWindowMetadataProviding,
    @unchecked Sendable
{
    func runningApplications() async -> [CodexApplicationDescriptor] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.map { application in
                let version = application.bundleURL
                    .flatMap(Bundle.init(url:))?
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String
                return CodexApplicationDescriptor(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    version: version
                )
            }
        }
    }

    func visibleWindows() async -> [QuartzWindowDescriptor] {
        await Task.detached(priority: .utility) {
            let options: CGWindowListOption = [
                .optionOnScreenOnly,
                .excludeDesktopElements
            ]
            let dictionaries = CGWindowListCopyWindowInfo(
                options,
                kCGNullWindowID
            ) as? [[String: Any]] ?? []
            return Self.decode(dictionaries)
        }.value
    }

    func windows(withIDs ids: [CGWindowID]) async -> [QuartzWindowDescriptor] {
        guard !ids.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            let numbers = ids.map(NSNumber.init(value:)) as CFArray
            let dictionaries = CGWindowListCreateDescriptionFromArray(numbers)
                as? [[String: Any]] ?? []
            return Self.decode(dictionaries)
        }.value
    }

    private static func decode(
        _ dictionaries: [[String: Any]]
    ) -> [QuartzWindowDescriptor] {
        dictionaries.compactMap { dictionary in
            guard
                let id = (dictionary[kCGWindowNumber as String] as? NSNumber)?
                    .uint32Value,
                let ownerPID =
                    (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?
                    .int32Value,
                let bounds = dictionary[kCGWindowBounds as String]
                    as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?
                    .intValue,
                let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?
                    .doubleValue,
                let sharingState =
                    (dictionary[kCGWindowSharingState as String] as? NSNumber)?
                    .intValue
            else {
                return nil
            }
            let isOnScreen =
                (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?
                .boolValue ?? true
            return QuartzWindowDescriptor(
                id: id,
                ownerPID: ownerPID,
                frame: frame,
                layer: layer,
                alpha: alpha,
                sharingState: sharingState,
                isOnScreen: isOnScreen,
                name: dictionary[kCGWindowName as String] as? String
            )
        }
    }
}

protocol PetWindowLocating: Sendable {
    func discover() async -> PetWindowObservation?
    func refresh(_ previous: PetWindowObservation) async
        -> PetWindowObservation?
}

actor CodexPetWindowLocator: PetWindowLocating {
    static let codexBundleIdentifier = "com.openai.codex"

    private let provider: any CodexWindowMetadataProviding
    private let profiles: [PetWindowMatchProfile]

    init(
        provider: any CodexWindowMetadataProviding =
            SystemCodexWindowMetadataProvider(),
        profiles: [PetWindowMatchProfile] = [.codex26_721]
    ) {
        self.provider = provider
        self.profiles = profiles
    }

    func discover() async -> PetWindowObservation? {
        let applications = await provider.runningApplications().filter {
            $0.bundleIdentifier == Self.codexBundleIdentifier
        }
        guard !applications.isEmpty else { return nil }

        let windows = await provider.visibleWindows()
        let matches = applications.flatMap { application in
            observations(
                windows: windows.filter {
                    $0.ownerPID == application.processIdentifier
                },
                application: application
            )
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func refresh(
        _ previous: PetWindowObservation
    ) async -> PetWindowObservation? {
        guard
            let application = await provider.runningApplications().first(
                where: {
                    $0.processIdentifier == previous.processIdentifier
                        && $0.bundleIdentifier == Self.codexBundleIdentifier
                }
            )
        else {
            return nil
        }

        let windows = await provider.windows(withIDs: previous.trackedWindowIDs)
        let matches = observations(windows: windows, application: application)
            .filter { $0.anchorWindowID == previous.anchorWindowID }
        return matches.count == 1 ? matches[0] : nil
    }

    private func observations(
        windows: [QuartzWindowDescriptor],
        application: CodexApplicationDescriptor
    ) -> [PetWindowObservation] {
        profiles.flatMap { profile in
            let usable = windows.filter(Self.isUsable)
            let anchors = usable.filter {
                $0.layer == profile.anchorLayer
                    && profile.anchorWidthRange.contains($0.frame.width)
                    && profile.anchorHeightRange.contains($0.frame.height)
            }
            let matches: [PetWindowObservation] = anchors.compactMap {
                anchor -> PetWindowObservation? in
                let validating = usable.filter {
                    $0.id != anchor.id
                        && $0.ownerPID == anchor.ownerPID
                        && $0.layer == profile.validatingLayer
                        && Self.isValidatingWindow($0, profile: profile)
                        && Self.distance($0.frame, anchor.frame)
                            <= profile.maximumAdjacencyDistance
                }
                let hasComposition = validating.contains {
                    profile.compositionWidthRange.contains($0.frame.width)
                        && profile.compositionHeightRange.contains(
                            $0.frame.height
                        )
                }
                guard hasComposition else { return nil }

                let tracked = ([anchor] + validating).sorted { $0.id < $1.id }
                let obstacles = validating
                    .filter {
                        profile.compactWidthRange.contains($0.frame.width)
                            && profile.compactHeightRange.contains(
                                $0.frame.height
                            )
                    }
                    .sorted { $0.id < $1.id }
                    .map(\.frame)
                return PetWindowObservation(
                    anchorWindowID: anchor.id,
                    trackedWindowIDs: tracked.map(\.id),
                    anchorFrame: anchor.frame,
                    obstacleFrames: obstacles,
                    processIdentifier: application.processIdentifier,
                    appVersion: application.version
                )
            }
            return matches
        }
    }

    private static func isUsable(_ window: QuartzWindowDescriptor) -> Bool {
        window.isOnScreen
            && window.alpha > 0.01
            && window.sharingState != 0
            && window.frame.width > 0
            && window.frame.height > 0
    }

    private static func isValidatingWindow(
        _ window: QuartzWindowDescriptor,
        profile: PetWindowMatchProfile
    ) -> Bool {
        let isComposition =
            profile.compositionWidthRange.contains(window.frame.width)
                && profile.compositionHeightRange.contains(window.frame.height)
        let isCompact =
            profile.compactWidthRange.contains(window.frame.width)
                && profile.compactHeightRange.contains(window.frame.height)
        return isComposition || isCompact
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let horizontal = max(
            max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX),
            0
        )
        let vertical = max(
            max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY),
            0
        )
        return hypot(horizontal, vertical)
    }
}
