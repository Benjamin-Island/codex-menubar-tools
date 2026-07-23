import AppKit
import SwiftUI

struct PetDragCaptureView: NSViewRepresentable {
    let onClick: () -> Void
    let onDragBegan: () -> Void
    let onDirectionChanged: (PetDockEdge) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    func makeNSView(context: Context) -> PetDragNSView {
        let view = PetDragNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: PetDragNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: PetDragNSView) {
        view.onClick = onClick
        view.onDragBegan = onDragBegan
        view.onDirectionChanged = onDirectionChanged
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }
}

final class PetDragNSView: NSView {
    var onClick: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDirectionChanged: (PetDockEdge) -> Void = { _ in }
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: (CGSize) -> Void = { _ in }

    private var mouseDownLocation: NSPoint?
    private var isDraggingPet = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        isDraggingPet = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation else { return }
        let translation = translation(from: mouseDownLocation)
        if !isDraggingPet,
           hypot(translation.width, translation.height) >= 3 {
            isDraggingPet = true
            onDragBegan()
        }
        guard isDraggingPet else { return }
        if abs(translation.width) > 2 {
            onDirectionChanged(translation.width < 0 ? .left : .right)
        }
        onDragChanged(translation)
    }

    override func mouseUp(with event: NSEvent) {
        guard let mouseDownLocation else { return }
        let translation = translation(from: mouseDownLocation)
        if isDraggingPet {
            onDragEnded(translation)
        } else {
            onClick()
        }
        self.mouseDownLocation = nil
        isDraggingPet = false
    }

    private func translation(from start: NSPoint) -> CGSize {
        let current = NSEvent.mouseLocation
        return CGSize(
            width: current.x - start.x,
            height: start.y - current.y
        )
    }
}
