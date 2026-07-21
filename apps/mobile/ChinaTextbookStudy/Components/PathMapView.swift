import SwiftUI

/// Duolingo-style lesson path.
///
/// - Column-centered zig-zag with gentle offsets
/// - Node types cycle: star, star, video, chest, star, star, video, trophy
/// - Current node bobs gently, wears a real unit-progress ring + "开始" pill
/// - Tapping any node opens an anchored start popup (title · lesson n/m · +XP)
/// - Tapping a locked node shakes it and shows a hint
struct PathMapView: View {
    let lessons: [PathMapNode]
    let onTap: (PathMapNode) -> Void

    private static let offsets: [CGFloat] = [0, 35, 45, 35, 0, -35, -45, -35]
    private let nodeSize: CGFloat = 72
    private let stepY: CGFloat = 96
    private let bannerHeight: CGFloat = 72
    private var stageWidth: CGFloat { 340 }

    @State private var selectedIndex: Int?
    @State private var lockedShake = 0
    @State private var lockedIndex: Int?
    @State private var showLockedToast = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .top) {
                    decorations

                    ForEach(unitBannerPositions, id: \.unitNumber) { banner in
                        unitBannerView(banner)
                            .position(x: stageWidth / 2, y: banner.y)
                    }

                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, node in
                        nodeView(node: node, index: index)
                            .position(nodePosition(at: index))
                            .id(node.id)
                    }

                    // Dismiss layer + anchored start popup
                    if let sel = selectedIndex, sel < lessons.count {
                        Color.black.opacity(0.001)
                            .frame(width: stageWidth, height: totalHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(Motion.press) { selectedIndex = nil } }

                        startPopup(index: sel)
                            .position(
                                x: stageWidth / 2,
                                y: nodePosition(at: sel).y + nodeSize / 2 + 96
                            )
                            .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                            .zIndex(10)
                    }
                }
                .frame(width: stageWidth, height: totalHeight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .background(DuoColors.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) { lockedToast }
            .onAppear { scrollToCurrent(proxy, animated: false) }
            .onChange(of: lessons) { _, _ in scrollToCurrent(proxy, animated: true) }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current = lessons.first(where: { $0.status == .current }),
              let idx = lessons.firstIndex(where: { $0.id == current.id }), idx > 1 else { return }
        let scroll = { proxy.scrollTo(current.id, anchor: .center) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if animated { withAnimation(.easeOut(duration: 0.4)) { scroll() } } else { scroll() }
        }
    }

    // MARK: - Start popup

    @ViewBuilder
    private func startPopup(index: Int) -> some View {
        let node = lessons[index]
        let unitNodes = lessons.filter { $0.unitNumber == node.unitNumber }
        let lessonNo = (unitNodes.firstIndex(where: { $0.id == node.id }) ?? 0) + 1
        let accent = node.status == .completed ? DuoColors.bee : DuoColors.primary

        VStack(spacing: 0) {
            CalloutTriangle().fill(accent).frame(width: 22, height: 11)
            VStack(alignment: .leading, spacing: 12) {
                Text(node.title)
                    .duoFont(.subhead)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("第 \(lessonNo) / \(unitNodes.count) 节 · +20 XP")
                    .duoFont(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Button {
                    selectedIndex = nil
                    onTap(node)
                } label: {
                    Text(node.status == .completed ? "再练一次" : "开始")
                        .duoFont(.button)
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lesson-start")
            }
            .padding(16)
            .frame(width: stageWidth - 48)
            .background(accent, in: .rect(cornerRadius: Radius.large))
        }
    }

    // MARK: - Layout calculations

    private func bannerOffsetBefore(index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        var offset: CGFloat = 0
        for i in 1..<min(index + 1, lessons.count) {
            if lessons[i].unitNumber != lessons[i - 1].unitNumber {
                offset += bannerHeight + 24
            }
        }
        return offset
    }

    private func nodePosition(at index: Int) -> CGPoint {
        let xOffset = Self.offsets[index % Self.offsets.count]
        let extraY = bannerOffsetBefore(index: index)
        return CGPoint(
            x: stageWidth / 2 + xOffset,
            y: nodeSize / 2 + CGFloat(index) * stepY + extraY + bannerHeight + 24
        )
    }

    private var totalHeight: CGFloat {
        guard let last = lessons.indices.last else { return nodeSize }
        return nodePosition(at: last).y + nodeSize / 2 + 160
    }

    // MARK: - Unit banner

    private struct BannerPosition: Hashable {
        let unitNumber: Int
        let unitTitle: String
        let y: CGFloat
    }

    private var unitBannerPositions: [BannerPosition] {
        var result: [BannerPosition] = []
        if let first = lessons.first {
            result.append(BannerPosition(unitNumber: first.unitNumber, unitTitle: first.unitTitle, y: bannerHeight / 2 + 4))
        }
        for i in 1..<max(1, lessons.count) {
            if lessons[i].unitNumber != lessons[i - 1].unitNumber {
                let prevPos = nodePosition(at: i - 1)
                let nextPos = nodePosition(at: i)
                result.append(BannerPosition(unitNumber: lessons[i].unitNumber, unitTitle: lessons[i].unitTitle, y: (prevPos.y + nextPos.y) / 2))
            }
        }
        return result
    }

    @ViewBuilder
    private func unitBannerView(_ banner: BannerPosition) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(DuoColors.primaryDark)
                .frame(width: stageWidth - 16, height: bannerHeight)
                .offset(y: 4)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(banner.unitNumber) 单元")
                        .duoFont(.micro)
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(banner.unitTitle)
                        .duoFont(.subhead)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)

                Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.vertical, 14)

                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64)
            }
            .frame(width: stageWidth - 16, height: bannerHeight)
            .background(DuoColors.primary, in: .rect(cornerRadius: Radius.card))
        }
    }

    // MARK: - Node rendering

    enum NodeKind { case star, video, chest, trophy }

    private func nodeKind(at index: Int, node: PathMapNode) -> NodeKind {
        let isLastOfUnit: Bool = {
            guard index < lessons.count - 1 else { return true }
            return lessons[index + 1].unitNumber != node.unitNumber
        }()
        if isLastOfUnit { return .trophy }
        switch index % 4 {
        case 2: return .video
        case 3: return .chest
        default: return .star
        }
    }

    /// Fraction of the node's unit already completed (drives the current ring).
    private func unitProgress(for node: PathMapNode) -> Double {
        let unitNodes = lessons.filter { $0.unitNumber == node.unitNumber }
        guard !unitNodes.isEmpty else { return 0 }
        let done = unitNodes.filter { $0.status == .completed }.count
        return Double(done) / Double(unitNodes.count)
    }

    @ViewBuilder
    private func nodeView(node: PathMapNode, index: Int) -> some View {
        let kind = nodeKind(at: index, node: node)
        let isCurrent = node.status == .current

        Button {
            if node.status == .locked {
                lockedIndex = index
                HapticEngine.shared.wrong()
                withAnimation(.linear(duration: 0.4)) { lockedShake += 1 }
                showLockedHint()
            } else {
                HapticEngine.shared.tap(); SFXEngine.shared.play(.tap)
                withAnimation(Motion.bounce) {
                    selectedIndex = (selectedIndex == index) ? nil : index
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isCurrent { progressRing(progress: unitProgress(for: node)) }

                    Circle()
                        .fill(nodeShadowColor(status: node.status))
                        .frame(width: nodeSize, height: nodeSize)
                        .offset(y: 5)

                    Circle()
                        .fill(nodeBackground(status: node.status))
                        .frame(width: nodeSize, height: nodeSize)

                    nodeIcon(node: node, kind: kind)
                }
                if isCurrent { startPill }
            }
            .modifier(ShakeEffect(animatableData: CGFloat(lockedIndex == index ? lockedShake : 0)))
            .modifier(IdleBob(active: isCurrent))
        }
        .buttonStyle(PathNodeButtonStyle())
        .accessibilityIdentifier("lesson-row-\(node.id)")
        .accessibilityLabel("\(node.title), \(node.status == .completed ? "已完成" : node.status == .current ? "当前" : "未解锁")")
    }

    // MARK: - Node visuals

    private func progressRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(DuoColors.surfaceAlt, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 6]))
                .frame(width: nodeSize + 18, height: nodeSize + 18)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(DuoColors.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: nodeSize + 18, height: nodeSize + 18)
                .rotationEffect(.degrees(-90))
                .animation(Motion.reveal, value: progress)
        }
    }

    private var startPill: some View {
        Text("开始")
            .duoFont(.caption)
            .tracking(0.6)
            .foregroundStyle(DuoColors.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DuoColors.bg, in: .capsule)
            .overlay { Capsule().strokeBorder(DuoColors.border, lineWidth: 2) }
            .offset(y: 6)
    }

    private func nodeBackground(status: LessonStatus) -> Color {
        switch status {
        case .completed: return DuoColors.bee
        case .current:   return DuoColors.primary
        case .locked:    return DuoColors.lockedNodeTop
        }
    }

    private func nodeShadowColor(status: LessonStatus) -> Color {
        switch status {
        case .completed: return Color(hex: 0xCC9E00)
        case .current:   return DuoColors.primaryDark
        case .locked:    return DuoColors.lockedNodeLedge
        }
    }

    @ViewBuilder
    private func nodeIcon(node: PathMapNode, kind: NodeKind) -> some View {
        let color: Color = node.status == .locked ? DuoColors.inkSofter : .white

        switch kind {
        case .star:
            if node.status == .completed, node.stars > 0 {
                VStack(spacing: 2) {
                    Image(systemName: "crown.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(color)
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < node.stars ? "star.fill" : "star")
                                .font(.system(size: 7))
                                .foregroundStyle(color.opacity(i < node.stars ? 1 : 0.5))
                        }
                    }
                }
            } else {
                Image(systemName: "star.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(color)
            }
        case .video:
            Image(systemName: "video.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(color)
        case .chest:
            Image(systemName: "shippingbox.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(color)
        case .trophy:
            ZStack {
                Image(systemName: "gearshape.fill").font(.system(size: 44, weight: .bold)).foregroundStyle(color.opacity(0.9))
                Image(systemName: "flag.fill").font(.system(size: 16, weight: .black)).foregroundStyle(DuoColors.danger)
            }
        }
    }

    // MARK: - Locked toast

    @ViewBuilder
    private var lockedToast: some View {
        if showLockedToast {
            Text("先完成前面的课程再解锁哦")
                .duoFont(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DuoColors.ink.opacity(0.9), in: .capsule)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showLockedHint() {
        withAnimation(Motion.reveal) { showLockedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.3)) { showLockedToast = false }
        }
    }

    // MARK: - Decorations

    @ViewBuilder
    private var decorations: some View {
        if lessons.count >= 4 {
            let starPos = nodePosition(at: min(3, lessons.count - 1))
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 14))
                Image(systemName: "star.fill").font(.system(size: 16))
                Image(systemName: "star.fill").font(.system(size: 14))
            }
            .foregroundStyle(DuoColors.surfaceAlt)
            .position(x: stageWidth - 40, y: starPos.y + 4)
        }
    }
}

// MARK: - Idle bob (current node breathes)

private struct IdleBob: ViewModifier {
    let active: Bool
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: active && up ? -6 : 0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

// MARK: - Press style

private struct PathNodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(y: configuration.isPressed ? 0.94 : 1.0, anchor: .bottom)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Callout triangle (shared by the start popup)

struct CalloutTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Data model

struct PathMapNode: Identifiable, Hashable {
    let id: String
    let title: String
    let unitNumber: Int
    let unitTitle: String
    let status: LessonStatus
    let stars: Int
}
