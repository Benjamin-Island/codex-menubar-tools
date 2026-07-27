import CoreGraphics
import Foundation

enum PetUsageBadgePlacement {
    static let badgeSize = CGSize(width: 48, height: 28)
    static let summarySize = CGSize(width: 306, height: 66)
    static let gap: CGFloat = 8
    static let edgeMargin: CGFloat = 4

    static func appKitFrame(
        from quartzFrame: CGRect,
        quartzScreenFrame: CGRect,
        appKitScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: appKitScreenFrame.minX
                + quartzFrame.minX
                - quartzScreenFrame.minX,
            y: appKitScreenFrame.minY
                + quartzScreenFrame.maxY
                - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    static func badgeFrame(
        anchorFrame: CGRect,
        obstacleFrames: [CGRect],
        visibleFrame: CGRect,
        previousFrame: CGRect?
    ) -> CGRect? {
        let candidates = [
            CGRect(
                x: anchorFrame.maxX + gap,
                y: anchorFrame.minY,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.minX - gap - badgeSize.width,
                y: anchorFrame.minY,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.maxX + gap,
                y: anchorFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.minX - gap - badgeSize.width,
                y: anchorFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            )
        ]
        let safe = candidates.enumerated().filter {
            isSafe(
                $0.element,
                visibleFrame: visibleFrame,
                excludedFrames: [anchorFrame] + obstacleFrames
            )
        }
        guard !safe.isEmpty else { return nil }
        guard let previousFrame else { return safe[0].element }
        return safe.min {
            let lhsDistance = squaredDistance(
                $0.element.origin,
                previousFrame.origin
            )
            let rhsDistance = squaredDistance(
                $1.element.origin,
                previousFrame.origin
            )
            if lhsDistance == rhsDistance {
                return $0.offset < $1.offset
            }
            return lhsDistance < rhsDistance
        }?.element
    }

    static func summaryFrame(
        badgeFrame: CGRect,
        anchorFrame: CGRect,
        obstacleFrames: [CGRect],
        visibleFrame: CGRect
    ) -> CGRect? {
        let right = CGRect(
            x: badgeFrame.maxX + gap,
            y: badgeFrame.midY - summarySize.height / 2,
            width: summarySize.width,
            height: summarySize.height
        )
        let left = CGRect(
            x: badgeFrame.minX - gap - summarySize.width,
            y: badgeFrame.midY - summarySize.height / 2,
            width: summarySize.width,
            height: summarySize.height
        )
        let above = CGRect(
            x: badgeFrame.midX - summarySize.width / 2,
            y: badgeFrame.maxY + gap,
            width: summarySize.width,
            height: summarySize.height
        )
        let below = CGRect(
            x: badgeFrame.midX - summarySize.width / 2,
            y: badgeFrame.minY - gap - summarySize.height,
            width: summarySize.width,
            height: summarySize.height
        )
        let horizontal = badgeFrame.midX >= anchorFrame.midX
            ? [right, left]
            : [left, right]
        let vertical = badgeFrame.midY >= visibleFrame.midY
            ? [below, above]
            : [above, below]
        return (horizontal + vertical).first {
            isSafe(
                $0,
                visibleFrame: visibleFrame,
                excludedFrames: [badgeFrame, anchorFrame] + obstacleFrames
            )
        }
    }

    private static func isSafe(
        _ candidate: CGRect,
        visibleFrame: CGRect,
        excludedFrames: [CGRect]
    ) -> Bool {
        let insetVisibleFrame = visibleFrame.insetBy(
            dx: edgeMargin,
            dy: edgeMargin
        )
        return !insetVisibleFrame.isNull
            && insetVisibleFrame.contains(candidate)
            && !excludedFrames.contains(where: candidate.intersects)
    }

    private static func squaredDistance(
        _ lhs: CGPoint,
        _ rhs: CGPoint
    ) -> CGFloat {
        let x = lhs.x - rhs.x
        let y = lhs.y - rhs.y
        return x * x + y * y
    }
}
