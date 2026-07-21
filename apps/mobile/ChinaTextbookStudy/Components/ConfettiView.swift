import SwiftUI
import UIKit

/// CAEmitterLayer-based confetti burst — ported from `ConfettiCanvas.tsx`.
/// ~140 particles × 3 shapes × 8 Duolingo colors.
struct ConfettiView: UIViewRepresentable {
    var active: Bool

    func makeUIView(context: Context) -> ConfettiHostView {
        ConfettiHostView()
    }

    func updateUIView(_ uiView: ConfettiHostView, context: Context) {
        if active {
            uiView.fire()
        }
    }
}

final class ConfettiHostView: UIView {
    private var hasFired = false

    func fire() {
        guard !hasFired else { return }
        hasFired = true

        let colors: [UIColor] = [
            UIColor(red: 0.345, green: 0.8, blue: 0.008, alpha: 1),     // feather
            UIColor(red: 0.11, green: 0.69, blue: 0.965, alpha: 1),     // macaw
            UIColor(red: 1, green: 0.784, blue: 0, alpha: 1),           // bee
            UIColor(red: 1, green: 0.294, blue: 0.294, alpha: 1),       // cardinal
            UIColor(red: 0.808, green: 0.51, blue: 1, alpha: 1),        // beetle
            UIColor(red: 1, green: 0.588, blue: 0, alpha: 1),           // fox
            UIColor(red: 0.537, green: 0.886, blue: 0.098, alpha: 1),   // maskGreen
            UIColor(red: 0.078, green: 0.831, blue: 0.957, alpha: 1),   // sea
        ]

        // Two fountain points at 30% and 70% width
        for xFraction in [0.3, 0.7] {
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = CGPoint(x: bounds.width * xFraction, y: bounds.height * 0.25)
            emitter.emitterSize = CGSize(width: 10, height: 10)
            emitter.emitterShape = .point
            emitter.renderMode = .additive

            var cells: [CAEmitterCell] = []
            for color in colors {
                let cell = CAEmitterCell()
                cell.birthRate = 10  // ~70 per fountain over burst
                cell.lifetime = 3.2
                cell.lifetimeRange = 0.5
                cell.velocity = 300
                cell.velocityRange = 100
                cell.emissionRange = .pi * 0.4
                cell.emissionLongitude = -.pi / 2 // upward
                cell.spin = 3
                cell.spinRange = 6
                cell.scale = 0.08
                cell.scaleRange = 0.04
                cell.yAcceleration = 280  // gravity
                cell.alphaSpeed = -0.3     // fade in last portion

                cell.color = color.cgColor

                // Random shape: small square for rect/ribbon
                cell.contents = makeConfettiImage(size: CGSize(width: 12, height: 12), color: color)

                cells.append(cell)
            }

            emitter.emitterCells = cells
            layer.addSublayer(emitter)

            // Stop emitting after a short burst
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                emitter.birthRate = 0
            }
            // Remove layer after particles die
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                emitter.removeFromSuperlayer()
            }
        }
    }

    private func makeConfettiImage(size: CGSize, color: UIColor) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            color.setFill()
            // Random shape: 60% rect, 40% circle
            if Int.random(in: 0...4) < 3 {
                ctx.fill(CGRect(origin: .zero, size: size))
            } else {
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }
        return img.cgImage
    }
}
