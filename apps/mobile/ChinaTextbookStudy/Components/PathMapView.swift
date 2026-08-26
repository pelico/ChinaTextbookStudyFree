import SwiftUI

/// Duolingo-style lesson path.
///
/// - Column-centered zig-zag with gentle offsets
/// - Lesson glyphs cycle star/video with a trophy closing each unit; chest
///   nodes are REAL reward slots (every 5th lesson, see `Chest.slots`) that
///   the caller claims via `onTap`
/// - Current node bobs gently, wears a real unit-progress ring + "开始" pill
/// - Tapping a lesson opens an anchored start popup (title · lesson n/m · +XP)
/// - Tapping a locked node shakes it and shows a hint
struct PathMapView: View {
    let lessons: [PathMapNode]
    let onTap: (PathMapNode) -> Void
    /// 单元 banner 的指南按钮（Wave E2）：打开该单元的知识手册。
    var onGuideTap: ((Int) -> Void)? = nil
    /// 锁定单元 banner 的「⚡ 跳到这里」（Wave E2）：发起跳级测试。
    var onJumpTap: ((Int) -> Void)? = nil

    private static let offsets: [CGFloat] = [0, 35, 45, 35, 0, -35, -45, -35]
    private let nodeSize: CGFloat = 72
    private let stepY: CGFloat = 96
    private let bannerHeight: CGFloat = 72
    private var stageWidth: CGFloat { 340 }

    @State private var selectedIndex: Int?
    @State private var lockedShake = 0
    @State private var lockedIndex: Int?
    @State private var showLockedToast = false
    /// 锁定提示文案 —— 挑战节点与普通节点的解锁条件不同。
    @State private var lockedToastText = "先完成前面的课程再解锁哦"

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
            // Follow the learner's progress, but only when the current node
            // actually moves — a chest claim also mutates `lessons`, and
            // yanking the viewport away from the chest would be jarring.
            // 挑战节点解锁不抢占自动滚动的锚点（下一节普通课才是主线）。
            .onChange(of: lessons.first(where: { $0.status == .current && $0.kind != .exam })?.id) { _, _ in
                scrollToCurrent(proxy, animated: true)
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current = lessons.first(where: { $0.status == .current && $0.kind != .exam }),
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
        let isExam = node.kind == .exam
        let unitNodes = lessons.filter { $0.kind == .lesson && $0.unitNumber == node.unitNumber }
        let lessonNo = (unitNodes.firstIndex(where: { $0.id == node.id }) ?? 0) + 1
        let accent: Color = isExam
            ? DuoColors.beetle
            : (node.status == .completed ? DuoColors.bee : DuoColors.primary)
        let subtitle: String = isExam
            ? "\(node.questionCount) 道题 · ⚔️ 挑战双倍 XP · 最多 +\(maxXp(for: node)) XP"
            : "第 \(lessonNo) / \(unitNodes.count) 节" +
              (node.questionCount > 0 ? " · 最多 +\(maxXp(for: node)) XP" : "")

        VStack(spacing: 0) {
            CalloutTriangle().fill(accent).frame(width: 22, height: 11)
            VStack(alignment: .leading, spacing: 12) {
                Text(isExam ? "⚔️ \(node.title)" : node.title)
                    .duoFont(.subhead)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .duoFont(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                if isExam, node.status != .completed {
                    Text("答对 80% 以上就能征服这个单元，赢得金色奖杯！")
                        .duoFont(.micro)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Button {
                    selectedIndex = nil
                    onTap(node)
                } label: {
                    Text(isExam
                         ? (node.status == .completed ? "再战一次" : "开始挑战")
                         : (node.status == .completed ? "再练一次" : "开始"))
                        .duoFont(.button)
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(isExam ? "exam-start" : "lesson-start")
            }
            .padding(16)
            .frame(width: stageWidth - 48)
            .background(accent, in: .rect(cornerRadius: Radius.large))
        }
    }

    /// Honest XP ceiling for the start bubble: full marks + perfect bonus,
    /// plus the first-3-star bonus while it's still winnable, weekend-aware.
    /// 挑战节点按 ×2 口径展示（与结算一致）。
    private func maxXp(for node: PathMapNode) -> Int {
        Economy.xpForLesson(
            correctCount: node.questionCount,
            perfect: true,
            firstPerfect: node.stars < 3,
            isWeekend: Economy.isWeekend(),
            isExam: node.kind == .exam
        )
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

    /// 该单元是否整体锁定（所有普通课都还没解锁）—— 跳级入口只挂在这种
    /// banner 上；含当前节点的单元不满足。
    private func isUnitLocked(_ unitNumber: Int) -> Bool {
        let unitLessons = lessons.filter { $0.kind == .lesson && $0.unitNumber == unitNumber }
        guard !unitLessons.isEmpty else { return false }
        return unitLessons.allSatisfy { $0.status == .locked }
    }

    @ViewBuilder
    private func unitBannerView(_ banner: BannerPosition) -> some View {
        let showJump = onJumpTap != nil && isUnitLocked(banner.unitNumber)

        ZStack {
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(DuoColors.primaryDark)
                .frame(width: stageWidth - 16, height: bannerHeight)
                .offset(y: 4)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: showJump ? 6 : 4) {
                    if showJump {
                        // 锁定单元：标题压成一行，给「跳到这里」腾出空间。
                        Text("第 \(banner.unitNumber) 单元 · \(banner.unitTitle)")
                            .duoFont(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Button {
                            HapticEngine.shared.tap()
                            SFXEngine.shared.play(.tap)
                            onJumpTap?(banner.unitNumber)
                        } label: {
                            HStack(spacing: 5) {
                                Text("⚡").font(.system(size: 12))
                                Text("跳到这里")
                                    .duoFont(.caption)
                            }
                            .foregroundStyle(DuoColors.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.white, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("jump-here-u\(banner.unitNumber)")
                        .accessibilityLabel("跳级测试，跳到第 \(banner.unitNumber) 单元")
                    } else {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)

                Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.vertical, 14)

                // 单元知识手册入口（ios-path-5 收尾）：从假图标变成真按钮。
                Button {
                    HapticEngine.shared.tap()
                    SFXEngine.shared.play(.tap)
                    onGuideTap?(banner.unitNumber)
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: bannerHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onGuideTap == nil)
                .accessibilityIdentifier("unit-guide-u\(banner.unitNumber)")
                .accessibilityLabel("第 \(banner.unitNumber) 单元知识手册")
            }
            .frame(width: stageWidth - 16, height: bannerHeight)
            .background(DuoColors.primary, in: .rect(cornerRadius: Radius.card))
        }
    }

    // MARK: - Node rendering

    enum NodeKind { case star, video, chest, trophy, exam }

    private func nodeKind(at index: Int, node: PathMapNode) -> NodeKind {
        if node.kind == .chest { return .chest }
        if node.kind == .exam { return .exam }
        let hasLaterLessonInUnit = lessons[(index + 1)...].contains {
            $0.kind == .lesson && $0.unitNumber == node.unitNumber
        }
        if !hasLaterLessonInUnit { return .trophy }
        return index % 4 == 2 ? .video : .star
    }

    /// Whether the learner has zero progress in this book — the current (first)
    /// node then wears a pulsing halo as an onboarding "start here" guide.
    private var isFreshBook: Bool {
        !lessons.contains { $0.status == .completed }
    }

    /// Fraction of the node's unit already completed (drives the current ring).
    private func unitProgress(for node: PathMapNode) -> Double {
        let unitNodes = lessons.filter { $0.kind == .lesson && $0.unitNumber == node.unitNumber }
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
                // 挑战节点的解锁条件是「本单元全通」，提示要说清楚。
                lockedToastText = node.kind == .exam
                    ? "完成本单元全部课程，就能开启单元挑战啦"
                    : "先完成前面的课程再解锁哦"
                showLockedHint()
            } else if node.kind == .chest {
                // Unlocked chest: claim directly (no start popup). Already-
                // opened chests just acknowledge the tap.
                HapticEngine.shared.tap()
                if !node.chestClaimed {
                    SFXEngine.shared.play(.tap)
                    onTap(node)
                }
            } else {
                HapticEngine.shared.tap(); SFXEngine.shared.play(.tap)
                withAnimation(Motion.bounce) {
                    selectedIndex = (selectedIndex == index) ? nil : index
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // 新手引导（onboarding 收尾）：全书零进度时给第一个节点一圈
                    // 脉冲光环，指着「从这里开始」。挑战节点不参与主线引导。
                    if isCurrent && isFreshBook && node.kind != .exam { PulseHalo(size: nodeSize) }
                    if isCurrent && node.kind != .exam {
                        progressRing(progress: unitProgress(for: node))
                    }

                    Circle()
                        .fill(nodeLedgeColor(for: node))
                        .frame(width: nodeSize, height: nodeSize)
                        .offset(y: 5)

                    Circle()
                        .fill(nodeTopColor(for: node))
                        .frame(width: nodeSize, height: nodeSize)

                    nodeIcon(node: node, kind: kind)
                }
                if isCurrent {
                    if node.kind == .exam { examPill } else { startPill }
                }
            }
            .modifier(ShakeEffect(animatableData: CGFloat(lockedIndex == index ? lockedShake : 0)))
            .modifier(IdleBob(active: isCurrent))
        }
        .buttonStyle(PathNodeButtonStyle())
        .accessibilityIdentifier(
            node.kind == .chest ? "chest-node-\(node.id)"
            : node.kind == .exam ? "exam-node-\(node.id)"
            : "lesson-row-\(node.id)")
        .accessibilityLabel(node.kind == .chest
            ? "宝箱, \(node.status == .locked ? "未解锁" : node.chestClaimed ? "已领取" : "可领取")"
            : node.kind == .exam
            ? "\(node.title), \(node.status == .locked ? "未解锁" : node.conquered ? "已征服" : node.status == .completed ? "已完成" : "可挑战")"
            : "\(node.title), \(node.status == .completed ? "已完成" : node.status == .current ? "当前" : "未解锁")")
    }

    /// 节点顶面颜色（挑战节点走紫金配色，征服后金色态）。
    private func nodeTopColor(for node: PathMapNode) -> Color {
        if node.kind == .chest && node.chestClaimed { return DuoColors.lockedNodeTop }
        if node.kind == .exam {
            if node.status == .locked { return DuoColors.lockedNodeTop }
            return node.conquered ? DuoColors.bee : DuoColors.beetle
        }
        return nodeBackground(status: node.status)
    }

    /// 节点 3D 底座颜色。
    private func nodeLedgeColor(for node: PathMapNode) -> Color {
        if node.kind == .chest && node.chestClaimed { return DuoColors.lockedNodeLedge }
        if node.kind == .exam {
            if node.status == .locked { return DuoColors.lockedNodeLedge }
            return node.conquered ? Color(hex: 0xCC9E00) : Color(hex: 0xA45FD6)
        }
        return nodeShadowColor(status: node.status)
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

    /// 解锁但未通关的挑战节点：紫色「挑战」小药丸。
    private var examPill: some View {
        Text("挑战")
            .duoFont(.caption)
            .tracking(0.6)
            .foregroundStyle(DuoColors.beetle)
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
            if node.chestClaimed {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DuoColors.bee.opacity(0.55))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(DuoColors.primary)
                        .offset(x: 5, y: 5)
                }
            } else {
                Image(systemName: "shippingbox.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(color)
            }
        case .trophy:
            ZStack {
                Image(systemName: "gearshape.fill").font(.system(size: 44, weight: .bold)).foregroundStyle(color.opacity(0.9))
                Image(systemName: "flag.fill").font(.system(size: 16, weight: .black)).foregroundStyle(DuoColors.danger)
            }
        case .exam:
            // 紫金奖杯挑战节点：未解锁灰奖杯；可挑战紫底金奖杯；
            // 通关未征服加小对勾；accuracy ≥ 0.8 征服 = 金底白奖杯 + 星星。
            if node.status == .locked {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(DuoColors.inkSofter)
            } else if node.conquered {
                VStack(spacing: 1) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }
            } else if node.status == .completed {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(DuoColors.bee)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .offset(x: 6, y: 5)
                }
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(DuoColors.bee)
            }
        }
    }

    // MARK: - Locked toast

    @ViewBuilder
    private var lockedToast: some View {
        if showLockedToast {
            Text(lockedToastText)
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

// MARK: - Pulse halo (onboarding "start here" guide)

/// A soft ring that repeatedly swells out of the node — draws a brand-new
/// learner's eye to the very first lesson.
private struct PulseHalo: View {
    let size: CGFloat
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(DuoColors.primary.opacity(pulsing ? 0 : 0.55), lineWidth: 4)
            .frame(width: size + 8, height: size + 8)
            .scaleEffect(pulsing ? 1.55 : 1.0)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
            .allowsHitTesting(false)
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

// MARK: - Node building

/// Shared builder for a book's path nodes: lesson nodes with status/stars, a
/// chest node after every 5th lesson of a unit (see `Chest.slots`), plus a
/// trophy「单元挑战」node closing each unit that ships an exam lesson
/// (Wave E1). Used by both the Home tab and BookDetailView so the two paths
/// can't drift.
@MainActor
enum PathNodeBuilder {
    static func nodes(
        bookId: String,
        lessons: [PathLessonMeta],
        progressStore: ProgressStore,
        examSlots: [ExamSlot] = []
    ) -> [PathMapNode] {
        var foundCurrent = false
        let chestByAfterLesson = Dictionary(
            uniqueKeysWithValues: Chest.slots(bookId: bookId, lessons: lessons)
                .map { ($0.afterLessonId, $0) }
        )
        let examByUnit = Dictionary(
            uniqueKeysWithValues: examSlots.map { ($0.unitNumber, $0) }
        )
        var nodes: [PathMapNode] = []
        for (i, row) in lessons.enumerated() {
            let stars = progressStore.stars(for: row.id) ?? 0
            let isCompleted = stars > 0
            let status: LessonStatus
            if isCompleted {
                status = .completed
            } else if !foundCurrent {
                status = .current
                foundCurrent = true
            } else {
                status = .locked
            }
            nodes.append(PathMapNode(
                id: row.id,
                title: row.title,
                unitNumber: row.unitNumber,
                unitTitle: row.unitTitle,
                status: status,
                stars: stars,
                questionCount: row.questionCount
            ))
            if let slot = chestByAfterLesson[row.id] {
                nodes.append(PathMapNode(
                    id: slot.id,
                    title: "宝箱",
                    unitNumber: slot.unitNumber,
                    unitTitle: slot.unitTitle,
                    status: isCompleted ? .completed : .locked,
                    stars: 0,
                    kind: .chest,
                    chestClaimed: progressStore.isChestClaimed(slot.id)
                ))
            }
            // 单元最后一节普通课之后挂「单元挑战」奖杯节点：
            // 本单元全部普通课完成才解锁；accuracy ≥ 0.8 视为征服（金色态）。
            let isLastOfUnit = i + 1 >= lessons.count || lessons[i + 1].unitNumber != row.unitNumber
            if isLastOfUnit, let exam = examByUnit[row.unitNumber] {
                let unitDone = lessons
                    .filter { $0.unitNumber == row.unitNumber }
                    .allSatisfy { progressStore.isLessonCompleted($0.id) }
                let result = progressStore.progress.completedLessons[exam.lessonId]
                let examStatus: LessonStatus = result != nil
                    ? .completed
                    : unitDone ? .current : .locked
                nodes.append(PathMapNode(
                    id: exam.lessonId,
                    title: exam.title,
                    unitNumber: exam.unitNumber,
                    unitTitle: exam.unitTitle,
                    status: examStatus,
                    stars: result?.stars ?? 0,
                    kind: .exam,
                    conquered: (result?.accuracy ?? 0) >= 0.8,
                    questionCount: exam.questionCount
                ))
            }
        }
        return nodes
    }
}

// MARK: - Data model

struct PathMapNode: Identifiable, Hashable {
    enum Kind: Hashable { case lesson, chest, exam }

    let id: String
    let title: String
    let unitNumber: Int
    let unitTitle: String
    let status: LessonStatus
    let stars: Int
    var kind: Kind = .lesson
    /// Chest nodes only: whether the reward was already collected.
    var chestClaimed: Bool = false
    /// Exam nodes only: accuracy ≥ 0.8 conquered the unit (golden trophy).
    var conquered: Bool = false
    /// Lesson nodes only: drives the "+N XP" line in the start popup (0 = unknown).
    var questionCount: Int = 0
}
