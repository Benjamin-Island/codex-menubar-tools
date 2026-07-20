import AppKit

struct UsageIndicatorRenderer {
    static let imageSize = NSSize(width: 34, height: 14)

    func image(label: String, progress: Double?) -> NSImage {
        let image = NSImage(size: Self.imageSize)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let size = Self.imageSize
        context.clear(CGRect(origin: .zero, size: size))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let rect = CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
        let outerPath = CGPath(
            roundedRect: rect,
            cornerWidth: rect.height / 2,
            cornerHeight: rect.height / 2,
            transform: nil
        )

        context.addPath(outerPath)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.52).cgColor)
        context.fillPath()

        if let progress {
            let innerRect = rect.insetBy(dx: 1.8, dy: 2.0)
            let clamped = min(1.0, max(0.0, progress))
            let progressWidth = innerRect.width * clamped

            if progressWidth > 0 {
                let progressRect = CGRect(
                    x: innerRect.minX,
                    y: innerRect.minY,
                    width: progressWidth,
                    height: innerRect.height
                )

                context.addPath(CGPath(
                    roundedRect: progressRect,
                    cornerWidth: innerRect.height / 2,
                    cornerHeight: innerRect.height / 2,
                    transform: nil
                ))
                context.setFillColor(NSColor.labelColor.withAlphaComponent(0.96).cgColor)
                context.fillPath()
            }
        }

        drawKnockout(label: label, in: size)
        return image
    }

    private func drawKnockout(label: String, in size: NSSize) {
        let text = label as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let textRect = CGRect(x: 0, y: 1.0, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        text.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
