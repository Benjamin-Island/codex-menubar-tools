import AppKit

struct StatusItemRenderer {
    static let imageSize = NSSize(width: 60, height: 16)

    func image(for presentation: StatusItemPresentation) -> NSImage {
        let image = NSImage(size: Self.imageSize)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        context.clear(CGRect(origin: .zero, size: Self.imageSize))
        drawUsage(presentation, context: context)
        drawSessions(presentation.sessionLabel)
        return image
    }

    private func drawUsage(_ presentation: StatusItemPresentation, context: CGContext) {
        let rect = CGRect(x: 0.5, y: 1.5, width: 33, height: 13)
        let outer = CGPath(
            roundedRect: rect,
            cornerWidth: rect.height / 2,
            cornerHeight: rect.height / 2,
            transform: nil
        )
        context.addPath(outer)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.5).cgColor)
        context.fillPath()
        if let progress = presentation.progress {
            let inner = rect.insetBy(dx: 1.8, dy: 2)
            let width = inner.width * min(1, max(0, progress))
            if width > 0 {
                let progressRect = CGRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
                context.addPath(CGPath(
                    roundedRect: progressRect,
                    cornerWidth: inner.height / 2,
                    cornerHeight: inner.height / 2,
                    transform: nil
                ))
                context.setFillColor(NSColor.labelColor.cgColor)
                context.fillPath()
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSGraphicsContext.saveGraphicsState()
        context.setBlendMode(.clear)
        (presentation.usageLabel as NSString).draw(
            in: CGRect(x: 0, y: 2.1, width: 34, height: 13),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSessions(_ label: String) {
        let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)
        symbol?.draw(in: CGRect(x: 38, y: 3, width: 11, height: 11))
        (label as NSString).draw(
            at: CGPoint(x: 51, y: 2.3),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
