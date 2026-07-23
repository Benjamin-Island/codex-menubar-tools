import AppKit
import SwiftUI

enum PetAnimationState: Equatable {
    case idle
    case runningLeft
    case runningRight
    case peekingLeft
    case peekingRight
}

struct PetSpriteView: View {
    let pet: CodexPet
    let state: PetAnimationState
    private let image: NSImage?

    private let columns = 8
    private var rows: Int { pet.spriteVersionNumber == 2 ? 11 : 9 }

    init(pet: CodexPet, state: PetAnimationState) {
        self.pet = pet
        self.state = state
        image = NSImage(contentsOf: pet.spritesheetURL)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { context in
            if let image {
                let tick = Int(context.date.timeIntervalSinceReferenceDate / frameInterval)
                spriteSheet(image: image, frame: tick % animationFrameCount)
            } else {
                fallback
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pet.displayName) Codex pet")
        .accessibilityValue(accessibilityValue)
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
                    y: -CGFloat(spriteRow) * frameHeight
                )
        }
        .clipped()
    }

    private var spriteRow: Int {
        switch state {
        case .idle, .peekingLeft, .peekingRight:
            return 0
        case .runningRight:
            return 1
        case .runningLeft:
            return 2
        }
    }

    private var animationFrameCount: Int {
        switch state {
        case .idle, .peekingLeft, .peekingRight:
            return 7
        case .runningLeft, .runningRight:
            return 8
        }
    }

    private var frameInterval: TimeInterval {
        switch state {
        case .idle, .peekingLeft, .peekingRight:
            return 0.55
        case .runningLeft, .runningRight:
            return 0.15
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle:
            return "Idle"
        case .runningLeft:
            return "Running left"
        case .runningRight:
            return "Running right"
        case .peekingLeft:
            return "Peeking from left edge"
        case .peekingRight:
            return "Peeking from right edge"
        }
    }

    private var fallback: some View {
        Image(systemName: "pawprint.fill")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(.white)
    }
}
