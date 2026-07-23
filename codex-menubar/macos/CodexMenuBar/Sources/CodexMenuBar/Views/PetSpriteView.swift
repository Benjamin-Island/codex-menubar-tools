import AppKit
import SwiftUI

struct PetSpriteView: View {
    let pet: CodexPet
    let isActive: Bool
    private let image: NSImage?

    private let columns = 8
    private let animationFrameCount = 6
    private var rows: Int { pet.spriteVersionNumber == 2 ? 11 : 9 }

    init(pet: CodexPet, isActive: Bool) {
        self.pet = pet
        self.isActive = isActive
        image = NSImage(contentsOf: pet.spritesheetURL)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.22)) { context in
            if let image {
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.22)
                spriteSheet(image: image, frame: tick % animationFrameCount)
            } else {
                fallback
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pet.displayName) Codex pet")
        .accessibilityValue(isActive ? "Active" : "Idle")
    }

    private func spriteSheet(image: NSImage, frame: Int) -> some View {
        GeometryReader { proxy in
            let frameWidth = proxy.size.width
            let frameHeight = proxy.size.height
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: frameWidth * CGFloat(columns),
                    height: frameHeight * CGFloat(rows),
                    alignment: .topLeading
                )
                .offset(
                    x: -CGFloat(frame) * frameWidth,
                    y: -CGFloat(isActive ? 1 : 0) * frameHeight
                )
        }
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "pawprint.fill")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(.white)
    }
}
