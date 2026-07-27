import Foundation

struct PetUsageBadgeTrackingUpdate: Equatable, Sendable {
    let observation: PetWindowObservation?
    let isMoving: Bool
}

@MainActor
protocol PetUsageBadgeTracking: AnyObject {
    var onUpdate: (@MainActor (PetUsageBadgeTrackingUpdate) -> Void)? {
        get
        set
    }

    func start()
    func stop()
}

protocol PetUsageTrackerTiming: Sendable {
    func nowNanoseconds() async -> UInt64
    func sleep(for duration: Duration) async throws
}

struct SystemPetUsageTrackerTiming: PetUsageTrackerTiming {
    func nowNanoseconds() async -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
final class PetUsageBadgeTracker: PetUsageBadgeTracking {
    static let processDiscoveryInterval = Duration.seconds(5)
    static let petDiscoveryInterval = Duration.seconds(2)
    static let stableInterval = Duration.milliseconds(500)
    static let movingInterval = Duration.milliseconds(75)
    static let movementSettlingInterval = Duration.milliseconds(750)
    static let fullValidationInterval = Duration.seconds(10)

    var onUpdate: (@MainActor (PetUsageBadgeTrackingUpdate) -> Void)?

    private let locator: any PetWindowLocating
    private let codexIsRunning: @Sendable () async -> Bool
    private let timing: any PetUsageTrackerTiming
    private var task: Task<Void, Never>?
    private var currentObservation: PetWindowObservation?
    private var consecutiveFailures = 0
    private var movingUntilNanoseconds: UInt64 = 0
    private var fullValidationDueNanoseconds: UInt64 = 0

    init(
        locator: any PetWindowLocating,
        codexIsRunning: @escaping @Sendable () async -> Bool,
        timing: any PetUsageTrackerTiming = SystemPetUsageTrackerTiming()
    ) {
        self.locator = locator
        self.codexIsRunning = codexIsRunning
        self.timing = timing
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        currentObservation = nil
        consecutiveFailures = 0
        movingUntilNanoseconds = 0
        fullValidationDueNanoseconds = 0
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let now = await timing.nowNanoseconds()
            let delay = await scan(nowNanoseconds: now)
            do {
                try await timing.sleep(for: delay)
            } catch {
                break
            }
        }
    }

    private func scan(nowNanoseconds: UInt64) async -> Duration {
        guard await codexIsRunning() else {
            let hadObservation = currentObservation != nil
            currentObservation = nil
            consecutiveFailures = 0
            if hadObservation {
                onUpdate?(
                    PetUsageBadgeTrackingUpdate(
                        observation: nil,
                        isMoving: false
                    )
                )
            }
            return Self.processDiscoveryInterval
        }

        guard let previous = currentObservation else {
            let discovered = await locator.discover()
            guard let discovered else {
                if consecutiveFailures > 0 {
                    consecutiveFailures += 1
                    onUpdate?(
                        PetUsageBadgeTrackingUpdate(
                            observation: nil,
                            isMoving: false
                        )
                    )
                    return failureDelay(for: consecutiveFailures)
                }
                onUpdate?(
                    PetUsageBadgeTrackingUpdate(
                        observation: nil,
                        isMoving: false
                    )
                )
                return Self.petDiscoveryInterval
            }

            currentObservation = discovered
            consecutiveFailures = 0
            movingUntilNanoseconds = 0
            fullValidationDueNanoseconds = nowNanoseconds
                + Self.fullValidationInterval.nanoseconds
            onUpdate?(
                PetUsageBadgeTrackingUpdate(
                    observation: discovered,
                    isMoving: false
                )
            )
            return Self.stableInterval
        }

        let requiresFullValidation =
            nowNanoseconds >= fullValidationDueNanoseconds
        let refreshed = requiresFullValidation
            ? await locator.discover()
            : await locator.refresh(previous)
        guard let refreshed else {
            currentObservation = nil
            consecutiveFailures = max(1, consecutiveFailures + 1)
            onUpdate?(
                PetUsageBadgeTrackingUpdate(
                    observation: nil,
                    isMoving: false
                )
            )
            return failureDelay(for: consecutiveFailures)
        }

        let moved = refreshed.anchorFrame != previous.anchorFrame
        if moved {
            movingUntilNanoseconds = nowNanoseconds
                + Self.movementSettlingInterval.nanoseconds
        }
        currentObservation = refreshed
        consecutiveFailures = 0
        if requiresFullValidation {
            fullValidationDueNanoseconds = nowNanoseconds
                + Self.fullValidationInterval.nanoseconds
        }
        onUpdate?(
            PetUsageBadgeTrackingUpdate(
                observation: refreshed,
                isMoving: moved
            )
        )

        return nowNanoseconds < movingUntilNanoseconds
            ? Self.movingInterval
            : Self.stableInterval
    }

    private func failureDelay(for failureCount: Int) -> Duration {
        switch failureCount {
        case 1:
            .seconds(1)
        case 2:
            .seconds(2)
        default:
            .seconds(5)
        }
    }
}

private extension Duration {
    var nanoseconds: UInt64 {
        let components = self.components
        let seconds = UInt64(max(0, components.seconds))
        let attoseconds = UInt64(max(0, components.attoseconds))
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
