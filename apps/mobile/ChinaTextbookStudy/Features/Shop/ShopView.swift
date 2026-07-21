import SwiftUI

/// The gem shop — functional power-ups plus the cosmetic collection.
struct ShopView: View {
    @ObservedObject var progressStore: ProgressStore
    @State private var flash: String?

    private let refillCost = 350
    private let freezeCost = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                balanceHeader

                if let flash {
                    Text(flash)
                        .duoFont(.caption)
                        .foregroundStyle(DuoColors.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DuoColors.primary.opacity(0.14), in: .rect(cornerRadius: Radius.control))
                        .transition(.opacity)
                }

                powerUps
                cosmeticSection("聪聪皮肤", items: Cosmetics.mascotSkins)
                cosmeticSection("界面主题", items: Cosmetics.uiThemes.map(\.item))
                cosmeticSection("课程背景", items: Cosmetics.lessonBackdrops.map(\.item))
            }
            .padding(20)
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("商店")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Balance

    private var balanceHeader: some View {
        HStack(spacing: 14) {
            balanceChip(icon: "diamond.fill", value: progressStore.gems, tint: DuoColors.secondary)
            balanceChip(icon: "heart.fill", value: progressStore.hearts, tint: DuoColors.danger)
            Spacer()
        }
    }

    private func balanceChip(icon: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .heavy)).foregroundStyle(tint)
            Text("\(value)").duoNumeral(.subhead).foregroundStyle(DuoColors.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(tint.opacity(0.12), in: .capsule)
    }

    // MARK: - Power-ups

    private var powerUps: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("生命 & 连击")

            functionalRow(
                icon: "heart.fill", tint: DuoColors.danger,
                title: "补满爱心", subtitle: progressStore.hearts >= ProgressStore.maxHearts ? "爱心已满" : "立即恢复 5 颗爱心",
                cost: refillCost,
                enabled: progressStore.hearts < ProgressStore.maxHearts && progressStore.gems >= refillCost
            ) {
                if progressStore.buyHeartRefill(cost: refillCost) { win("爱心已补满！") } else { fail() }
            }

            functionalRow(
                icon: "snowflake", tint: DuoColors.secondary,
                title: "连胜护盾", subtitle: "当前拥有 \(progressStore.streakFreezes) 个 · 断签时自动顶替",
                cost: freezeCost,
                enabled: progressStore.gems >= freezeCost
            ) {
                if progressStore.buyStreakFreeze(cost: freezeCost) { win("已购买连胜护盾！") } else { fail() }
            }
        }
    }

    private func functionalRow(icon: String, tint: Color, title: String, subtitle: String, cost: Int, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: icon).font(.system(size: 22, weight: .heavy)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).duoFont(.subhead).foregroundStyle(DuoColors.ink)
                    Text(subtitle).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                Spacer()
                costPill(cost, enabled: enabled)
            }
            .padding(14)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func costPill(_ cost: Int, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill").font(.system(size: 12, weight: .heavy))
            Text("\(cost)").duoNumeral(.caption)
        }
        .foregroundStyle(enabled ? DuoColors.secondary : DuoColors.inkSofter)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background((enabled ? DuoColors.secondary : DuoColors.inkSofter).opacity(0.16), in: .capsule)
    }

    // MARK: - Cosmetics

    private func cosmeticSection(_ title: String, items: [CosmeticItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        cosmeticTile(item)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func cosmeticTile(_ item: CosmeticItem) -> some View {
        let owned = progressStore.isOwned(item.id)
        let equipped = progressStore.isEquipped(item.id)
        let affordable = progressStore.gems >= item.cost
        return Button {
            tapCosmetic(item, owned: owned, equipped: equipped, affordable: affordable)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .fill(item.rarity.color.opacity(0.16))
                        .frame(width: 108, height: 92)
                    Image(systemName: cosmeticSymbol(item))
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(item.rarity.color)
                }
                .overlay(alignment: .topTrailing) {
                    if equipped {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DuoColors.primary)
                            .padding(6)
                    } else if owned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(item.rarity.color)
                            .padding(6)
                    }
                }

                Text(item.name).duoFont(.caption).foregroundStyle(DuoColors.ink).lineLimit(1)

                Group {
                    if equipped {
                        Text("使用中").duoFont(.micro).foregroundStyle(DuoColors.primary)
                    } else if owned {
                        Text("点击使用").duoFont(.micro).foregroundStyle(DuoColors.secondary)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "diamond.fill").font(.system(size: 10, weight: .heavy))
                            Text("\(item.cost)").duoNumeral(.micro)
                        }
                        .foregroundStyle(affordable ? DuoColors.secondary : DuoColors.inkSofter)
                    }
                }
            }
            .frame(width: 116)
            .padding(.vertical, 10)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(equipped ? DuoColors.primary : DuoColors.border, lineWidth: equipped ? 2.5 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func tapCosmetic(_ item: CosmeticItem, owned: Bool, equipped: Bool, affordable: Bool) {
        if equipped { return }
        if owned {
            HapticEngine.shared.tap(); SFXEngine.shared.play(.tap)
            progressStore.equipCosmetic(item)
        } else if affordable {
            if progressStore.buyCosmetic(item) {
                progressStore.equipCosmetic(item)
                HapticEngine.shared.success(); SFXEngine.shared.play(.unlock)
                win("已解锁「\(item.name)」！")
            } else { fail() }
        } else {
            fail("宝石不够，继续学习赚取更多吧")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text).duoFont(.caption).tracking(1).foregroundStyle(DuoColors.inkMuted)
    }

    private func win(_ msg: String) {
        withAnimation(Motion.reveal) { flash = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { flash = nil } }
    }
    private func fail(_ msg: String = "宝石不够") {
        HapticEngine.shared.wrong()
        withAnimation(Motion.reveal) { flash = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { flash = nil } }
    }

    private func cosmeticSymbol(_ item: CosmeticItem) -> String {
        switch item.id {
        case "skin_graduate", "skin_laurel": return "graduationcap.fill"
        case "skin_glasses": return "eyeglasses"
        case "skin_party": return "party.popper.fill"
        case "skin_crown": return "crown.fill"
        case "skin_wizard": return "wand.and.stars"
        case "skin_astronaut": return "airplane"
        case "skin_sunglasses": return "sunglasses.fill"
        case "skin_pirate": return "sailboat.fill"
        case "skin_headphones": return "headphones"
        case "skin_bowtie": return "figure.dress.line.vertical.figure"
        default: break
        }
        switch item.type {
        case .mascotSkin:     return "face.smiling.inverse"
        case .uiTheme:        return "paintpalette.fill"
        case .lessonBackdrop: return "photo.fill"
        }
    }
}
