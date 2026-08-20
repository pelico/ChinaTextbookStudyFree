import SwiftUI

/// 聪聪 — the panda cub mascot, rendered with SwiftUI Canvas/shapes.
/// (Originally ported from `apps/web/src/components/Mascot.tsx`'s owl, then
/// redesigned as a panda with purchasable accessory skins.)
///
/// Supports 8 moods, breathing animation, random blink, and 3 reaction types.
struct MascotView: View {
    var mood: MascotMood = .happy
    var size: CGFloat = 120
    var reactTo: MascotReaction? = nil
    var reactKey: Int = 0
    /// Explicit skin id — used by shop previews. When nil the equipped skin wins.
    var skin: String? = nil

    @ObservedObject private var progressStore = ProgressStore.shared
    private var activeSkin: String { skin ?? progressStore.equippedMascotSkin }

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

                // Equipped cosmetic on top of everything
                drawAccessory(context: context, s: s, skin: activeSkin)
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

    // MARK: - Cosmetic accessories
    //
    // Drawn last, on top of the panda. Head centre is (60,50) with r≈37,
    // ears sit at (34,30) / (86,30); the neck/chest area is around y≈88.

    private func drawAccessory(context ctx: GraphicsContext, s: CGFloat, skin: String) {
        let gold = Color(hex: 0xFFC800)
        let goldDark = Color(hex: 0xE0A800)
        let dark = Color(hex: 0x2E2E2E)

        func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
            var p = Path()
            guard let f = pts.first else { return p }
            p.move(to: CGPoint(x: f.0*s, y: f.1*s))
            for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0*s, y: q.1*s)) }
            p.closeSubpath()
            return p
        }

        switch skin {
        case "skin_graduate":
            // Mortarboard: band + diamond board + tassel
            ctx.fill(poly([(42,16),(78,16),(76,26),(44,26)]), with: .color(dark))
            ctx.fill(poly([(60,2),(100,17),(60,32),(20,17)]), with: .color(Color(hex: 0x1F1F1F)))
            var tas = Path()
            tas.move(to: CGPoint(x: 96*s, y: 18*s))
            tas.addQuadCurve(to: CGPoint(x: 100*s, y: 34*s), control: CGPoint(x: 103*s, y: 25*s))
            ctx.stroke(tas, with: .color(gold), style: StrokeStyle(lineWidth: 2.4*s, lineCap: .round))
            drawCircle(context: ctx, cx: 100*s, cy: 37*s, r: 4*s, fill: gold)

        case "skin_glasses":
            for cx in [45.0, 75.0] {
                drawCircle(context: ctx, cx: CGFloat(cx)*s, cy: 48*s, r: 12*s, fill: .clear, stroke: Color(hex: 0x4A3A2A), lineWidth: 2.6*s)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 57*s, y: 47*s)); bridge.addLine(to: CGPoint(x: 63*s, y: 47*s))
            ctx.stroke(bridge, with: .color(Color(hex: 0x4A3A2A)), lineWidth: 2.4*s)

        case "skin_sunglasses":
            ctx.fill(Path(roundedRect: CGRect(x: 31*s, y: 39*s, width: 27*s, height: 19*s), cornerRadius: 7*s), with: .color(Color(hex: 0x22262B)))
            ctx.fill(Path(roundedRect: CGRect(x: 62*s, y: 39*s, width: 27*s, height: 19*s), cornerRadius: 7*s), with: .color(Color(hex: 0x22262B)))
            var br = Path(); br.move(to: CGPoint(x: 58*s, y: 45*s)); br.addLine(to: CGPoint(x: 62*s, y: 45*s))
            ctx.stroke(br, with: .color(Color(hex: 0x22262B)), lineWidth: 4*s)
            var shine = Path()
            shine.move(to: CGPoint(x: 36*s, y: 54*s)); shine.addLine(to: CGPoint(x: 46*s, y: 42*s))
            ctx.stroke(shine, with: .color(.white.opacity(0.5)), lineWidth: 2.2*s)

        case "skin_crown":
            ctx.fill(poly([(30,28),(40,10),(50,22),(60,6),(70,22),(80,10),(90,28)]), with: .color(gold))
            ctx.fill(Path(roundedRect: CGRect(x: 30*s, y: 25*s, width: 60*s, height: 8*s), cornerRadius: 3*s), with: .color(goldDark))
            drawCircle(context: ctx, cx: 60*s, cy: 8*s, r: 3.2*s, fill: Color(hex: 0xFF6B6B))

        case "skin_party":
            ctx.fill(poly([(60,-4),(44,28),(76,28)]), with: .color(Color(hex: 0xFF6B9D)))
            ctx.fill(poly([(60,-4),(52,12),(68,12)]), with: .color(Color(hex: 0xFFD166)))
            ctx.fill(poly([(48,22),(72,22),(76,28),(44,28)]), with: .color(Color(hex: 0x4ECDC4)))
            drawCircle(context: ctx, cx: 60*s, cy: -6*s, r: 5*s, fill: .white)

        case "skin_wizard":
            ctx.fill(poly([(62,-8),(38,30),(86,30)]), with: .color(Color(hex: 0x7C3AED)))
            ctx.fill(Path(roundedRect: CGRect(x: 34*s, y: 26*s, width: 56*s, height: 9*s), cornerRadius: 4*s), with: .color(Color(hex: 0x5B21B6)))
            // little star
            ctx.fill(poly([(58,4),(60.6,10),(67,10),(62,14),(64,20),(58,16),(52,20),(54,14),(49,10),(55.4,10)]), with: .color(gold))

        case "skin_astronaut":
            drawCircle(context: ctx, cx: 60*s, cy: 48*s, r: 46*s, fill: Color(hex: 0xBFE3F7).opacity(0.30), stroke: Color(hex: 0xDCE9F0), lineWidth: 4*s)
            var glare = Path()
            glare.addArc(center: CGPoint(x: 60*s, y: 48*s), radius: 38*s,
                         startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            ctx.stroke(glare, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 5*s, lineCap: .round))

        case "skin_pirate":
            ctx.fill(poly([(18,26),(60,4),(102,26),(96,32),(24,32)]), with: .color(Color(hex: 0x1F2328)))
            ctx.fill(Path(roundedRect: CGRect(x: 22*s, y: 24*s, width: 76*s, height: 9*s), cornerRadius: 4*s), with: .color(Color(hex: 0x8B0000)))
            drawCircle(context: ctx, cx: 60*s, cy: 17*s, r: 5*s, fill: .white)
            // eye patch on the left eye
            drawCircle(context: ctx, cx: 45*s, cy: 48*s, r: 11*s, fill: Color(hex: 0x1F2328))
            var strap = Path()
            strap.move(to: CGPoint(x: 24*s, y: 40*s)); strap.addLine(to: CGPoint(x: 92*s, y: 44*s))
            ctx.stroke(strap, with: .color(Color(hex: 0x1F2328)), lineWidth: 2.6*s)

        case "skin_headphones":
            var band = Path()
            band.addArc(center: CGPoint(x: 60*s, y: 46*s), radius: 44*s,
                        startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(Color(hex: 0x1CB0F6)), style: StrokeStyle(lineWidth: 6*s, lineCap: .round))
            ctx.fill(Path(roundedRect: CGRect(x: 10*s, y: 40*s, width: 16*s, height: 26*s), cornerRadius: 7*s), with: .color(Color(hex: 0x1899D6)))
            ctx.fill(Path(roundedRect: CGRect(x: 94*s, y: 40*s, width: 16*s, height: 26*s), cornerRadius: 7*s), with: .color(Color(hex: 0x1899D6)))

        case "skin_laurel":
            for side in [-1.0, 1.0] {
                let dir = CGFloat(side)
                var arc = Path()
                arc.addArc(center: CGPoint(x: 60*s, y: 52*s), radius: 42*s,
                           startAngle: .degrees(dir > 0 ? 300 : 240),
                           endAngle: .degrees(dir > 0 ? 20 : 160),
                           clockwise: dir < 0)
                ctx.stroke(arc, with: .color(Color(hex: 0x4C9A2A)), style: StrokeStyle(lineWidth: 3.4*s, lineCap: .round))
                for k in 0..<4 {
                    let ang = (dir > 0 ? 310.0 : 230.0) + Double(k) * (dir > 0 ? 18.0 : -18.0)
                    let r = 42.0
                    let cx = 60 + cos(ang * .pi/180) * r
                    let cy = 52 + sin(ang * .pi/180) * r
                    drawEllipse(context: ctx, cx: CGFloat(cx)*s, cy: CGFloat(cy)*s, rx: 5*s, ry: 3*s, fill: Color(hex: 0x6ABE30))
                }
            }

        case "skin_bowtie":
            ctx.fill(poly([(44,88),(56,82),(56,96),(44,94)]), with: .color(Color(hex: 0xE5484D)))
            ctx.fill(poly([(76,88),(64,82),(64,96),(76,94)]), with: .color(Color(hex: 0xE5484D)))
            drawCircle(context: ctx, cx: 60*s, cy: 89*s, r: 4.6*s, fill: Color(hex: 0xB8353A))

        default:
            break   // skin_default — bare panda
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
