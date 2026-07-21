import SwiftUI

/// Today's three quests with live progress and a claim button per quest.
struct DailyQuestsCard: View {
    @ObservedObject var progressStore: ProgressStore

    private var quests: [Quest] { progressStore.todayQuests }
    private var claimableCount: Int {
        quests.filter { progressStore.isQuestComplete($0) && !progressStore.isQuestClaimed($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target").font(.system(size: 17, weight: .heavy)).foregroundStyle(DuoColors.fox)
                Text("每日任务").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                Spacer()
                if claimableCount > 0 {
                    Text("\(claimableCount) 个可领取")
                        .duoFont(.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(DuoColors.fox, in: .capsule)
                } else {
                    Text("每天 0 点刷新").duoFont(.micro).foregroundStyle(DuoColors.inkSofter)
                }
            }

            ForEach(quests) { quest in
                questRow(quest)
            }
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    @ViewBuilder
    private func questRow(_ quest: Quest) -> some View {
        let done = progressStore.isQuestComplete(quest)
        let claimed = progressStore.isQuestClaimed(quest)
        let current = min(progressStore.questProgress(quest), quest.target)
        let frac = Double(current) / Double(max(quest.target, 1))

        HStack(spacing: 12) {
            ZStack {
                Circle().fill((done ? DuoColors.primary : DuoColors.fox).opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: claimed ? "checkmark" : quest.kind.symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(done ? DuoColors.primary : DuoColors.fox)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(quest.title)
                    .duoFont(.caption)
                    .foregroundStyle(claimed ? DuoColors.inkSofter : DuoColors.ink)
                    .strikethrough(claimed, color: DuoColors.inkSofter)
                HStack(spacing: 8) {
                    StyledProgressBar(
                        progress: frac, height: 8,
                        fillColor: done ? DuoColors.primary : DuoColors.fox,
                        trackColor: DuoColors.surfaceAlt
                    )
                    Text("\(current)/\(quest.target)")
                        .duoNumeral(.micro)
                        .foregroundStyle(DuoColors.inkMuted)
                }
            }

            claimButton(quest, done: done, claimed: claimed)
        }
    }

    @ViewBuilder
    private func claimButton(_ quest: Quest, done: Bool, claimed: Bool) -> some View {
        if claimed {
            HStack(spacing: 3) {
                Image(systemName: "diamond.fill").font(.system(size: 10, weight: .heavy))
                Text("\(quest.reward)").duoNumeral(.micro)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(DuoColors.inkSofter)
            .frame(width: 74)
        } else if done {
            Button {
                if progressStore.claimQuest(quest) {
                    HapticEngine.shared.success()
                    SFXEngine.shared.play(.unlock)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "diamond.fill").font(.system(size: 10, weight: .heavy))
                    Text("\(quest.reward)").duoNumeral(.micro)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(ChunkySmallButtonStyle())
            .frame(width: 74)
            .accessibilityIdentifier("quest-claim-\(quest.id)")
        } else {
            HStack(spacing: 3) {
                Image(systemName: "diamond.fill").font(.system(size: 10, weight: .heavy))
                Text("\(quest.reward)").duoNumeral(.micro)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(DuoColors.secondary)
            .frame(width: 74)
        }
    }
}
