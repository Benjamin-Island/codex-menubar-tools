import CoreGraphics
import Foundation

enum PetUsageBadgePlacement {
    static let badgeSize = CGSize(width: 48, height: 28)
    static let summarySize = CGSize(width: 306, height: 66)
    static let badgeGap: CGFloat = 4
    static let summaryGap: CGFloat = 8
    static let anchorTransparencyInset: CGFloat = 32
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
        let canUseTransparentInset =
            anchorFrame.height
            >= anchorTransparencyInset * 2 + badgeSize.height
        let visualAnchorFrame = anchorFrame.insetBy(
            dx: 0,
            dy: canUseTransparentInset ? anchorTransparencyInset : 0
        )
        let candidates = [
            CGRect(
                x: anchorFrame.maxX + badgeGap,
                y: anchorFrame.minY,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.minX - badgeGap - badgeSize.width,
                y: anchorFrame.minY,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.maxX + badgeGap,
                y: anchorFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.minX - badgeGap - badgeSize.width,
                y: anchorFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.midX - badgeSize.width / 2,
                y: visualAnchorFrame.maxY + badgeGap,
                width: badgeSize.width,
                height: badgeSize.height
            ),
            CGRect(
                x: anchorFrame.midX - badgeSize.width / 2,
                y: visualAnchorFrame.minY - badgeGap - badgeSize.height,
                width: badgeSize.width,
                height: badgeSize.height
            )
        ]
        let safe = candidates.enumerated().filter {
            isBadgeSafe(
                $0.element,
                visibleFrame: visibleFrame,
                anchorFrame: anchorFrame,
                visualAnchorFrame: visualAnchorFrame,
                obstacleFrames: obstacleFrames
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
            x: badgeFrame.maxX + summaryGap,
            y: badgeFrame.midY - summarySize.height / 2,
            width: summarySize.width,
            height: summarySize.height
        )
        let left = CGRect(
            x: badgeFrame.minX - summaryGap - summarySize.width,
            y: badgeFrame.midY - summarySize.height / 2,
            width: summarySize.width,
            height: summarySize.height
        )
        let above = CGRect(
            x: badgeFrame.midX - summarySize.width / 2,
            y: badgeFrame.maxY + summaryGap,
            width: summarySize.width,
            height: summarySize.height
        )
        let below = CGRect(
            x: badgeFrame.midX - summarySize.width / 2,
            y: badgeFrame.minY - summaryGap - summarySize.height,
            width: summarySize.width,
            height: summarySize.height
        )
        let horizontal = badgeFrame.midX >= anchorFrame.midX
            ? [right, left]
            : [left, right]
        let vertical = badgeFrame.midY >= visibleFrame.midY
            ? [below, above]
            : [above, below]
        let insetVisibleFrame = visibleFrame.insetBy(
            dx: edgeMargin,
            dy: edgeMargin
        )
        let anchorAlignedX = min(
            max(
                anchorFrame.midX - summarySize.width / 2,
                insetVisibleFrame.minX
            ),
            insetVisibleFrame.maxX - summarySize.width
        )
        let anchorAlignedY = min(
            max(
                anchorFrame.midY - summarySize.height / 2,
                insetVisibleFrame.minY
            ),
            insetVisibleFrame.maxY - summarySize.height
        )
        let aboveAnchor = CGRect(
            x: anchorAlignedX,
            y: anchorFrame.maxY + summaryGap,
            width: summarySize.width,
            height: summarySize.height
        )
        let belowAnchor = CGRect(
            x: anchorAlignedX,
            y: anchorFrame.minY - summaryGap - summarySize.height,
            width: summarySize.width,
            height: summarySize.height
        )
        let rightOfAnchor = CGRect(
            x: anchorFrame.maxX + summaryGap,
            y: anchorAlignedY,
            width: summarySize.width,
            height: summarySize.height
        )
        let leftOfAnchor = CGRect(
            x: anchorFrame.minX - summaryGap - summarySize.width,
            y: anchorAlignedY,
            width: summarySize.width,
            height: summarySize.height
        )
        let anchorVertical = badgeFrame.midY >= anchorFrame.midY
            ? [aboveAnchor, belowAnchor]
            : [belowAnchor, aboveAnchor]
        let anchorHorizontal = badgeFrame.midX >= anchorFrame.midX
            ? [rightOfAnchor, leftOfAnchor]
            : [leftOfAnchor, rightOfAnchor]
        return (
            horizontal
                + vertical
                + anchorVertical
                + anchorHorizontal
        ).first {
            isSafe(
                $0,
                visibleFrame: visibleFrame,
                excludedFrames: [badgeFrame, anchorFrame] + obstacleFrames
            )
        }
    }

    private static func isBadgeSafe(
        _ candidate: CGRect,
        visibleFrame: CGRect,
        anchorFrame: CGRect,
        visualAnchorFrame: CGRect,
        obstacleFrames: [CGRect]
    ) -> Bool {
        let insetVisibleFrame = visibleFrame.insetBy(
            dx: edgeMargin,
            dy: edgeMargin
        )
        guard
            !insetVisibleFrame.isNull,
            insetVisibleFrame.contains(candidate),
            !candidate.intersects(visualAnchorFrame)
        else {
            return false
        }
        return !obstacleFrames.contains { obstacleFrame in
            let overlap = candidate.intersection(obstacleFrame)
            return !overlap.isNull && !anchorFrame.contains(overlap)
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
