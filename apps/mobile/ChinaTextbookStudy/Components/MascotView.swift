import SwiftUI

/// 聪聪 — the owl mascot, rendered with SwiftUI shapes.
/// Direct port of `apps/web/src/components/Mascot.tsx` SVG.
///
/// Supports 8 moods, breathing animation, random blink, and 3 reaction types.
struct MascotView: View {
    var mood: MascotMood = .happy
    var size: CGFloat = 120
    var reactTo: MascotReaction? = nil
    var reactKey: Int = 0

    // Animation state
    @State private var breatheY: CGFloat = 0
    @State private var breatheScale: CGFloat = 1
    @State private var blinkClosed = false
    @State private var reactionScale: CGFloat = 1
    @State private var reactionRotation: Double = 0
    @State private var reactionY: CGFloat = 0
    @State private var wingRotation: Double = -15
    @State private var showSweat = false
    @State private var showGlow = false

    private let eel = Color(hex: 0x3A3A3A)
    private let pandaBlack = Color(hex: 0x2E2E2E)
    private let bodyWhite = Color(hex: 0xFBFBFB)
    private let bodyShade = Color(hex: 0xE9EDEF)

    var body: some View {
        ZStack {
            // Golden glow (levelup reaction)
            if showGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DuoColors.bee.opacity(0.55), DuoColors.bee.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.7
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .transition(.opacity.combined(with: .scale))
            }

            Canvas { context, canvasSize in
                // ViewBox: 0 0 120 120 → scale to `size`. 聪聪 the panda cub.
                let s = canvasSize.width / 120

                // Ears (black rounded)
                drawCircle(context: context, cx: 34*s, cy: 30*s, r: 13*s, fill: pandaBlack)
                drawCircle(context: context, cx: 86*s, cy: 30*s, r: 13*s, fill: pandaBlack)

                // Arms (black paws at the sides)
                drawEllipse(context: context, cx: 22*s, cy: 78*s, rx: 9*s, ry: 15*s, fill: pandaBlack)
                drawEllipse(context: context, cx: 98*s, cy: 78*s, rx: 9*s, ry: 15*s, fill: pandaBlack)

                // Feet (black, bottom)
                drawEllipse(context: context, cx: 46*s, cy: 104*s, rx: 11*s, ry: 8*s, fill: pandaBlack)
                drawEllipse(context: context, cx: 74*s, cy: 104*s, rx: 11*s, ry: 8*s, fill: pandaBlack)

                // Head + body (white, one rounded blob)
                drawEllipse(context: context, cx: 60*s, cy: 82*s, rx: 34*s, ry: 30*s, fill: bodyWhite)
                drawEllipse(context: context, cx: 60*s, cy: 50*s, rx: 40*s, ry: 37*s, fill: bodyWhite)
                // Soft belly shade
                drawEllipse(context: context, cx: 60*s, cy: 84*s, rx: 20*s, ry: 18*s, fill: bodyShade.opacity(0.6))

                // Black eye patches (angled ovals around the eyes)
                drawEllipse(context: context, cx: 44*s, cy: 50*s, rx: 12*s, ry: 15*s, fill: pandaBlack)
                drawEllipse(context: context, cx: 76*s, cy: 50*s, rx: 12*s, ry: 15*s, fill: pandaBlack)

                // White eye sockets on top of the patches
                drawCircle(context: context, cx: 45*s, cy: 48*s, r: 8.5*s, fill: bodyWhite)
                drawCircle(context: context, cx: 75*s, cy: 48*s, r: 8.5*s, fill: bodyWhite)

                // Eyes (mood-dependent pupils)
                if blinkClosed && (mood == .happy || mood == .think || mood == .wave) {
                    drawBlinkEyes(context: context, s: s)
                } else {
                    drawEyes(context: context, s: s, mood: mood)
                }

                // Nose (black rounded triangle)
                var nose = Path()
                nose.move(to: CGPoint(x: 54*s, y: 60*s))
                nose.addQuadCurve(to: CGPoint(x: 66*s, y: 60*s), control: CGPoint(x: 60*s, y: 58*s))
                nose.addQuadCurve(to: CGPoint(x: 60*s, y: 68*s), control: CGPoint(x: 66*s, y: 66*s))
                nose.addQuadCurve(to: CGPoint(x: 54*s, y: 60*s), control: CGPoint(x: 54*s, y: 66*s))
                nose.closeSubpath()
                context.fill(nose, with: .color(pandaBlack))

                // Mouth (small smile under the nose)
                var mouth = Path()
                mouth.move(to: CGPoint(x: 60*s, y: 68*s))
                mouth.addLine(to: CGPoint(x: 60*s, y: 72*s))
                mouth.addQuadCurve(to: CGPoint(x: 68*s, y: 74*s), control: CGPoint(x: 64*s, y: 76*s))
                mouth.move(to: CGPoint(x: 60*s, y: 72*s))
                mouth.addQuadCurve(to: CGPoint(x: 52*s, y: 74*s), control: CGPoint(x: 56*s, y: 76*s))
                context.stroke(mouth, with: .color(pandaBlack), style: StrokeStyle(lineWidth: 2*s, lineCap: .round))

                // Embarrassed blush
                if mood == .embarrassed {
                    drawEllipse(context: context, cx: 32*s, cy: 62*s, rx: 6*s, ry: 3.5*s, fill: Color(hex: 0xFF9AA8).opacity(0.7))
                    drawEllipse(context: context, cx: 88*s, cy: 62*s, rx: 6*s, ry: 3.5*s, fill: Color(hex: 0xFF9AA8).opacity(0.7))
                }
            }
            .frame(width: size, height: size)

            // Sweat drop (wrong reaction)
            if showSweat {
                SweatDrop(size: size)
                    .transition(.opacity)
            }
        }
        .scaleEffect(reactionScale * breatheScale)
        .offset(y: reactionY + breatheY)
        .rotationEffect(.degrees(reactionRotation))
        .onAppear {
            startBreathing(); startBlinking()
            // If this mascot is mounted with a reaction already set (e.g. the
            // lesson feedback panel, which re-mounts per question), play it once
            // on appear — onChange(reactKey) only fires on subsequent changes.
            if reactTo != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { triggerReaction() }
            }
        }
        .onChange(of: reactKey) { _, _ in triggerReaction() }
        .accessibilityLabel("聪聪")
    }

    // MARK: - Eyes

    private func drawBlinkEyes(context: GraphicsContext, s: CGFloat) {
        // Closed eyes: curved lines
        var leftBlink = Path()
        leftBlink.move(to: CGPoint(x: 32*s, y: 48*s))
        leftBlink.addQuadCurve(to: CGPoint(x: 56*s, y: 48*s), control: CGPoint(x: 44*s, y: 52*s))
        context.stroke(leftBlink, with: .color(eel), lineWidth: 3*s)

        var rightBlink = Path()
        rightBlink.move(to: CGPoint(x: 64*s, y: 48*s))
        rightBlink.addQuadCurve(to: CGPoint(x: 88*s, y: 48*s), control: CGPoint(x: 76*s, y: 52*s))
        context.stroke(rightBlink, with: .color(eel), lineWidth: 3*s)
    }

    private func drawEyes(context: GraphicsContext, s: CGFloat, mood: MascotMood) {
        switch mood {
        case .cheer:
            var leftCheer = Path()
            leftCheer.move(to: CGPoint(x: 36*s, y: 48*s))
            leftCheer.addQuadCurve(to: CGPoint(x: 52*s, y: 48*s), control: CGPoint(x: 44*s, y: 40*s))
            context.stroke(leftCheer, with: .color(eel), lineWidth: 3*s)
            var rightCheer = Path()
            rightCheer.move(to: CGPoint(x: 68*s, y: 48*s))
            rightCheer.addQuadCurve(to: CGPoint(x: 84*s, y: 48*s), control: CGPoint(x: 76*s, y: 40*s))
            context.stroke(rightCheer, with: .color(eel), lineWidth: 3*s)

        case .sad:
            drawCircle(context: context, cx: 44*s, cy: 50*s, r: 4*s, fill: eel)
            drawCircle(context: context, cx: 76*s, cy: 50*s, r: 4*s, fill: eel)
            // Droopy eyebrows
            var browL = Path(); browL.move(to: CGPoint(x: 32*s, y: 38*s)); browL.addLine(to: CGPoint(x: 50*s, y: 42*s))
            context.stroke(browL, with: .color(eel), style: StrokeStyle(lineWidth: 2.5*s, lineCap: .round))
            var browR = Path(); browR.move(to: CGPoint(x: 88*s, y: 38*s)); browR.addLine(to: CGPoint(x: 70*s, y: 42*s))
            context.stroke(browR, with: .color(eel), style: StrokeStyle(lineWidth: 2.5*s, lineCap: .round))

        case .think:
            drawCircle(context: context, cx: 44*s, cy: 48*s, r: 5*s, fill: eel)
            drawCircle(context: context, cx: 45.5*s, cy: 46.5*s, r: 1.5*s, fill: .white)
            var thinkR = Path()
            thinkR.move(to: CGPoint(x: 68*s, y: 48*s))
            thinkR.addQuadCurve(to: CGPoint(x: 84*s, y: 48*s), control: CGPoint(x: 76*s, y: 46*s))
            context.stroke(thinkR, with: .color(eel), style: StrokeStyle(lineWidth: 2.5*s, lineCap: .round))

        case .surprise:
            drawCircle(context: context, cx: 44*s, cy: 48*s, r: 7*s, fill: eel)
            drawCircle(context: context, cx: 46*s, cy: 46*s, r: 2*s, fill: .white)
            drawCircle(context: context, cx: 76*s, cy: 48*s, r: 7*s, fill: eel)
            drawCircle(context: context, cx: 78*s, cy: 46*s, r: 2*s, fill: .white)

        case .proud:
            drawCircle(context: context, cx: 44*s, cy: 48*s, r: 5*s, fill: eel)
            drawCircle(context: context, cx: 45.5*s, cy: 46.5*s, r: 1.8*s, fill: .white)
            drawCircle(context: context, cx: 42*s, cy: 50*s, r: 0.9*s, fill: .white)
            drawCircle(context: context, cx: 76*s, cy: 48*s, r: 5*s, fill: eel)
            drawCircle(context: context, cx: 77.5*s, cy: 46.5*s, r: 1.8*s, fill: .white)
            drawCircle(context: context, cx: 74*s, cy: 50*s, r: 0.9*s, fill: .white)
            // Raised eyebrows
            var browLP = Path()
            browLP.move(to: CGPoint(x: 32*s, y: 38*s))
            browLP.addQuadCurve(to: CGPoint(x: 50*s, y: 40*s), control: CGPoint(x: 40*s, y: 34*s))
            context.stroke(browLP, with: .color(eel), style: StrokeStyle(lineWidth: 2.5*s, lineCap: .round))
            var browRP = Path()
            browRP.move(to: CGPoint(x: 88*s, y: 38*s))
            browRP.addQuadCurve(to: CGPoint(x: 70*s, y: 40*s), control: CGPoint(x: 80*s, y: 34*s))
            context.stroke(browRP, with: .color(eel), style: StrokeStyle(lineWidth: 2.5*s, lineCap: .round))

        case .embarrassed:
            drawCircle(context: context, cx: 44*s, cy: 50*s, r: 3.5*s, fill: eel)
            drawCircle(context: context, cx: 76*s, cy: 50*s, r: 3.5*s, fill: eel)

        case .happy, .wave:
            // Default happy eyes with highlight dot
            drawCircle(context: context, cx: 44*s, cy: 48*s, r: 5*s, fill: eel)
            drawCircle(context: context, cx: 45.5*s, cy: 46.5*s, r: 1.5*s, fill: .white)
            drawCircle(context: context, cx: 76*s, cy: 48*s, r: 5*s, fill: eel)
            drawCircle(context: context, cx: 77.5*s, cy: 46.5*s, r: 1.5*s, fill: .white)
        }
    }

    // MARK: - Canvas helpers

    private func drawEllipse(context: GraphicsContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, fill: Color, stroke: Color? = nil, lineWidth: CGFloat = 0) {
        let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(fill))
        if let stroke { context.stroke(path, with: .color(stroke), lineWidth: lineWidth) }
    }

    private func drawCircle(context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, fill: Color, stroke: Color? = nil, lineWidth: CGFloat = 0) {
        drawEllipse(context: context, cx: cx, cy: cy, rx: r, ry: r, fill: fill, stroke: stroke, lineWidth: lineWidth)
    }

    // MARK: - Animations

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            breatheY = -3
            breatheScale = 1.02
        }
    }

    private func startBlinking() {
        Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.5...6.0), repeats: false) { _ in
            Task { @MainActor in
                blinkClosed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    blinkClosed = false
                    startBlinking()
                }
            }
        }
    }

    private func triggerReaction() {
        guard let reaction = reactTo else { return }

        switch reaction {
        case .correct:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                reactionScale = 1.18
                reactionY = -6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    reactionScale = 1.0
                    reactionY = 0
                }
            }

        case .wrong:
            showSweat = true
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                reactionRotation = -8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) { reactionRotation = 8 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { reactionRotation = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showSweat = false }

        case .levelup:
            showGlow = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                reactionY = -18
                reactionScale = 1.1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    reactionY = 0
                    reactionScale = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.3)) { showGlow = false }
            }
        }
    }
}

// MARK: - Sweat Drop

private struct SweatDrop: View {
    let size: CGFloat
    @State private var dropY: CGFloat = -4
    @State private var dropOpacity: Double = 0

    var body: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: size * 0.1))
            .foregroundStyle(Color(hex: 0x7EC4F0))
            .offset(x: size * 0.27, y: size * 0.15 + dropY)
            .opacity(dropOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) {
                    dropY = 14
                    dropOpacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.3)) { dropOpacity = 0 }
                }
            }
    }
}
