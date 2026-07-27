enum PetUsageBadgeVisibility: Equatable {
    case hidden
    case badge
    case summary
}

enum PetUsageBadgeEvent: Equatable {
    case anchorFound
    case anchorLost
    case badgeClicked(summaryCanFit: Bool)
    case outsideClicked
    case escapePressed
    case movementStarted
    case disabled
}

enum PetUsageBadgeState {
    static func reduce(
        _ state: PetUsageBadgeVisibility,
        event: PetUsageBadgeEvent
    ) -> PetUsageBadgeVisibility {
        switch event {
        case .anchorLost, .disabled:
            return .hidden
        case .anchorFound:
            return state == .hidden ? .badge : state
        case let .badgeClicked(summaryCanFit):
            if state == .summary { return .badge }
            if state == .badge, summaryCanFit { return .summary }
            return state
        case .outsideClicked, .escapePressed, .movementStarted:
            return state == .summary ? .badge : state
        }
    }
}
