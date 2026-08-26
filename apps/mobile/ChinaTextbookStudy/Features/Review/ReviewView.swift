import SwiftUI

/// Mistake bank hub — a hero card that launches review, plus the due list.
struct ReviewView: View {
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    var body: some View {
        let due = progressStore.dueMistakes
        let all = progressStore.progress.mistakesBank

        ScrollView {
            VStack(spacing: 16) {
                hero(due: due.count, total: all.count)
                if !all.isEmpty {
                    bucketsBar
                }
                if !due.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("待复习").duoFont(.caption).tracking(1).foregroundStyle(DuoColors.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(due, id: \.question.id) { entry in
                            mistakeRow(entry)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("错题本")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(due: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            MascotView(mood: due > 0 ? .think : .proud, size: 96)

            if due > 0 {
                Text("有 \(due) 道题等你复习").duoFont(.heading).foregroundStyle(DuoColors.ink)
                Text("复习错题不掉血，还能赚经验值").duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                Button { path.append(.reviewRunner) } label: { Text("开始复习  答对每题 +5 XP") }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .accessibilityIdentifier("review-start")
            } else {
                Text(total == 0 ? "还没有错题" : "今天的复习完成啦！").duoFont(.heading).foregroundStyle(DuoColors.ink)
                Text(total == 0 ? "答错的题目会自动收进这里" : "\(total) 道题在记忆排程中等待")
                    .duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
            }

            HStack(spacing: 24) {
                miniStat(value: due, label: "今日待复习", tint: DuoColors.fox)
                miniStat(value: total, label: "错题总数", tint: DuoColors.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.large))
        .overlay { RoundedRectangle(cornerRadius: Radius.large).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    /// SRS 四桶概览：今天 / 明天 / 之后 / 已掌握（对照 web ReviewClient）。
    /// graduated 条目只进「已掌握」，其余按 nextReviewDate 分桶。
    private var bucketsBar: some View {
        let bank = progressStore.progress.mistakesBank
        let active = bank.filter { $0.graduated != true }
        let today = SRS.todayString()
        let tomorrow = SRS.dateString(daysFromNow: 1)
        let todayCount = active.filter { ($0.nextReviewDate ?? today) <= today }.count
        let tomorrowCount = active.filter { $0.nextReviewDate == tomorrow }.count
        let laterCount = active.filter { ($0.nextReviewDate ?? "") > tomorrow }.count
        let graduatedCount = bank.count - active.count

        return HStack(spacing: 8) {
            srsBucket(label: "今天", count: todayCount, tint: DuoColors.danger)
            srsBucket(label: "明天", count: tomorrowCount, tint: DuoColors.fox)
            srsBucket(label: "之后", count: laterCount, tint: DuoColors.secondary)
            srsBucket(label: "已掌握", count: graduatedCount, tint: DuoColors.primary)
        }
    }

    private func srsBucket(label: String, count: Int, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)").duoNumeral(.heading).foregroundStyle(tint)
            Text(label).duoFont(.micro).tracking(1).foregroundStyle(DuoColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(count) 道题")
    }

    private func miniStat(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").duoNumeral(.title).foregroundStyle(tint)
            Text(label).duoFont(.micro).foregroundStyle(DuoColors.inkMuted)
        }
    }

    private func mistakeRow(_ entry: MistakeEntry) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(DuoColors.fox.opacity(0.16)).frame(width: 38, height: 38)
                Text("\(entry.box ?? 1)").duoNumeral(.caption).foregroundStyle(DuoColors.fox)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.question.question).duoFont(.body).foregroundStyle(DuoColors.ink).lineLimit(2)
                Text("来自 \(entry.lessonTitle ?? entry.lessonId)").duoFont(.micro).foregroundStyle(DuoColors.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }
}
