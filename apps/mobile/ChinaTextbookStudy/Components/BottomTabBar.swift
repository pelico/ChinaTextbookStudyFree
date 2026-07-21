import SwiftUI

/// Duolingo-style bottom tab bar — flat, bold, single-tone glyphs.
///
/// - Adaptive background (white in light, navy in dark) with a top hairline.
/// - Active tab: filled glyph in its brand color on a soft tinted capsule.
/// - Inactive tab: the same glyph in muted gray (never a different shape).
/// - The active glyph bounces when selected.
struct BottomTabBar: View {
    @Binding var activeTab: AppTab
    @ObservedObject var progressStore: ProgressStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        .frame(height: 60)
        .padding(.top, 6)
        .background(DuoColors.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(DuoColors.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = activeTab == tab
        let badge = badge(for: tab)

        Button {
            guard activeTab != tab else { return }
            HapticEngine.shared.tap()
            withAnimation(Motion.press) { activeTab = tab }
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(tab.activeColor.opacity(0.14))
                            .frame(width: 60, height: 40)
                    }
                    Image(systemName: tab.symbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(isActive ? tab.activeColor : DuoColors.inkSofter)
                        .symbolEffect(.bounce, value: isActive)
                }
                .frame(width: 64, height: 44)

                if let count = badge?.count, count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(DuoColors.danger, in: .capsule)
                        .overlay(Capsule().strokeBorder(DuoColors.bg, lineWidth: 2))
                        .offset(x: 8, y: -2)
                } else if badge?.dot == true {
                    Circle()
                        .fill(DuoColors.danger)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(DuoColors.bg, lineWidth: 2))
                        .offset(x: 6, y: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private struct BadgeInfo { var count: Int?; var dot: Bool? }

    private func badge(for tab: AppTab) -> BadgeInfo? {
        switch tab {
        case .review:
            let due = progressStore.dueMistakes.count
            return due > 0 ? BadgeInfo(count: due) : nil
        default: return nil
        }
    }
}

// MARK: - Tab Definition

enum AppTab: String, CaseIterable {
    case learn, review, shop, profile

    var label: String {
        switch self {
        case .learn:   return "学习"
        case .review:  return "错题本"
        case .shop:    return "商店"
        case .profile: return "我的"
        }
    }

    var symbol: String {
        switch self {
        case .learn:   return "house.fill"
        case .review:  return "book.fill"
        case .shop:    return "bag.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var activeColor: Color {
        switch self {
        case .learn:   return DuoColors.primary       // green — the flagship tab
        case .review:  return DuoColors.fox           // orange
        case .shop:    return DuoColors.beetle        // purple
        case .profile: return DuoColors.secondary     // blue
        }
    }
}
