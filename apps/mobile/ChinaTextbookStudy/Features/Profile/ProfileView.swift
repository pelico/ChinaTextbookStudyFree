import SwiftUI

/// The learner's identity screen — avatar, stats, streak, achievements, settings.
struct ProfileView: View {
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    @State private var editingName = false
    @State private var nameDraft = ""

    private var achievementSnapshot: AchievementProgressSnapshot { progressStore.achievementSnapshot }
    private var unlockedCount: Int { progressStore.unlockedAchievementIds.count }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                header
                statGrid
                dailyGoalCard
                DailyQuestsCard(progressStore: progressStore)
                WeeklyReportCard(progressStore: progressStore)
                achievementsCard
                settingsRow
            }
            .padding(20)
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .alert("修改昵称", isPresented: $editingName) {
            TextField("昵称", text: $nameDraft)
            Button("保存") { progressStore.displayName = nameDraft }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(DuoColors.secondary.opacity(0.14)).frame(width: 120, height: 120)
                MascotView(mood: .happy, size: 104)
            }
            HStack(spacing: 8) {
                Text(progressStore.displayName).duoFont(.title).foregroundStyle(DuoColors.ink)
                Button {
                    nameDraft = progressStore.displayName
                    editingName = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DuoColors.inkSofter)
                }
                .buttonStyle(.plain)
            }
            Text("已完成 \(progressStore.totalCompletedLessons) 节 · \(progressStore.progress.xp) XP")
                .duoFont(.caption)
                .foregroundStyle(DuoColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(icon: "flame.fill", value: "\(progressStore.progress.streak)", label: "连续天数", tint: DuoColors.fox)
            statCard(icon: "bolt.fill", value: "\(progressStore.progress.xp)", label: "总经验值", tint: DuoColors.secondary)
            statCard(icon: "checkmark.seal.fill", value: "\(progressStore.totalCompletedLessons)", label: "完成课程", tint: DuoColors.primary)
            statCard(icon: "star.fill", value: "\(progressStore.perfectedLessonCount)", label: "完美通关", tint: DuoColors.bee)
        }
    }

    private func statCard(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 20, weight: .heavy)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value).duoNumeral(.heading).foregroundStyle(DuoColors.ink)
                Text(label).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    // MARK: - Daily goal

    private var dailyGoalCard: some View {
        HStack(spacing: 16) {
            DailyGoalRingView(progressStore: progressStore, size: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("今日目标").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                Text("\(progressStore.todayXp) / \(progressStore.dailyGoal) XP")
                    .duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                if progressStore.dailyGoalReached {
                    Text("今日目标已完成 🎉").duoFont(.caption).foregroundStyle(DuoColors.primary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    // MARK: - Achievements preview

    private var achievementsCard: some View {
        Button { path.append(.achievements) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(DuoColors.beetle.opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: "rosette").font(.system(size: 22, weight: .heavy)).foregroundStyle(DuoColors.beetle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("成就墙").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                    Text("已解锁 \(unlockedCount) / \(Achievements.all.count)").duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(DuoColors.inkSofter)
            }
            .padding(16)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        }
        .buttonStyle(.plain)
    }

    private var settingsRow: some View {
        Button { path.append(.settings) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(DuoColors.inkSofter.opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: "gearshape.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(DuoColors.inkMuted)
                }
                Text("设置").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(DuoColors.inkSofter)
            }
            .padding(16)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        }
        .buttonStyle(.plain)
    }
}
