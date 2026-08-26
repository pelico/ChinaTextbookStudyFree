import Foundation
import Combine

/// User progress store — port of apps/web/src/store/progress.ts.
///
/// State is persisted to `Application Support/cstf/progress.json` after every
/// mutation.
@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    static let maxHearts = 5
    /// 5 minutes per heart, matching web's HEART_RECHARGE_MS.
    static let heartRechargeSeconds: TimeInterval = 5 * 60

    @Published private(set) var progress: UserProgress

    /// Currently selected grade for the home screen (1-6, 0 = none picked yet).
    @Published var selectedGrade: Int

    /// The book currently displayed on the home/path tab. Nil = pick one first.
    @Published var activeBookId: String?

    /// Whether the first-run onboarding flow has been completed.
    @Published var hasCompletedOnboarding: Bool

    private static let progressFile = "progress.json"
    private static let prefsFile = "prefs.json"

    private struct Prefs: Codable {
        var selectedGrade: Int
        var activeBookId: String?
        var hasCompletedOnboarding: Bool?
    }

    init() {
        #if DEBUG
        // UI tests launch with `-uitest` to get a hermetic, deterministic state:
        // no persisted progress, onboarding already done, seed book selected.
        if ProcessInfo.processInfo.arguments.contains("-uitest") {
            var fresh = UserProgress(xp: 0, streak: 0, lastActiveDate: "", completedLessons: [:], mistakesBank: [])
            fresh.gems = 500
            fresh.hearts = Self.maxHearts
            self.progress = fresh
            self.selectedGrade = 1
            self.activeBookId = "g1up"
            self.hasCompletedOnboarding = true
            return
        }
        #endif

        if let restored = PersistenceService.read(UserProgress.self, from: Self.progressFile) {
            self.progress = restored
        } else {
            self.progress = UserProgress(
                xp: 0,
                streak: 0,
                lastActiveDate: "",
                completedLessons: [:],
                mistakesBank: []
            )
        }
        if let prefs = PersistenceService.read(Prefs.self, from: Self.prefsFile) {
            self.selectedGrade = prefs.selectedGrade
            self.activeBookId = prefs.activeBookId
            self.hasCompletedOnboarding = prefs.hasCompletedOnboarding ?? true  // existing users: skip
        } else {
            self.selectedGrade = 0
            self.activeBookId = nil
            self.hasCompletedOnboarding = false
        }
    }

    // MARK: - Mutations

    /// Award XP + record the result for a finished lesson.
    /// Stars are derived from accuracy: ≥0.95 → 3, ≥0.80 → 2, else 1.
    @discardableResult
    func completeLesson(
        lessonId: String,
        accuracy: Double,
        questionCount: Int,
        now: Date = Date()
    ) -> LessonOutcome {
        // Hearts may have recharged while the learner sat in the lesson —
        // settle the timer before anything below reads a stale count.
        tickHeartRecharge(now: now)

        let stars: Int
        switch accuracy {
        case 0.95...:  stars = 3
        case 0.80...:  stars = 2
        default:       stars = 1
        }
        // 10 XP per question, doubled for a 3-star clear
        let baseXp = questionCount * 10
        let bonus = stars == 3 ? baseXp : 0
        let xpGain = baseXp + bonus

        let result = LessonResult(
            lessonId: lessonId,
            stars: stars,
            accuracy: accuracy,
            completedAt: ISO8601DateFormatter().string(from: now)
        )

        let goal = dailyGoal
        // Read "today's XP so far" against the injected `now` (not the
        // wall-clock `todayXp` accessor) so the whole mutation shares one
        // notion of "today" — otherwise the one-time goal bonus repeats.
        let todayKey = SRS.todayString(now: now)
        let todayXpBefore = progress.lastXpDate == todayKey ? (progress.todayXp ?? 0) : 0
        let streakBefore = progress.streak
        let snapshotBefore = achievementSnapshot

        var p = progress
        rollDailyIfNeeded(&p, now: now)
        recordXP(&p, xpGain, now: now)
        p.dailyLessons = (p.dailyLessons ?? 0) + 1

        // Per-lesson gem drop — same economy as web's recordLessonComplete:
        // 3 base, +5 two-star, +10 three-star, +15 first perfect, +20 the
        // first time today's XP goal is crossed.
        let priorStars = p.completedLessons[lessonId]?.stars ?? 0
        var gemsGained = 3
        if stars == 2 { gemsGained += 5 }
        if stars == 3 { gemsGained += 10 }
        if stars == 3 && priorStars < 3 { gemsGained += 15 }

        // Take the best result so a re-run can only improve stars.
        if let prior = p.completedLessons[lessonId] {
            if stars >= prior.stars { p.completedLessons[lessonId] = result }
        } else {
            p.completedLessons[lessonId] = result
        }
        bumpStreak(&p, now: now)

        let dailyGoalReachedNow = todayXpBefore < goal && (p.todayXp ?? 0) >= goal
        if dailyGoalReachedNow { gemsGained += 20 }
        p.gems = (p.gems ?? 0) + gemsGained
        p.lifetimeGems = (p.lifetimeGems ?? 0) + gemsGained

        progress = p
        save()
        NotificationService.shared.rescheduleStreakReminder(streak: p.streak, studiedToday: true)

        return LessonOutcome(
            xpGained: xpGain,
            stars: stars,
            streakBefore: streakBefore,
            streakAfter: p.streak,
            dailyGoalReachedNow: dailyGoalReachedNow,
            gemsGained: gemsGained,
            newAchievements: Achievements.newlyUnlocked(before: snapshotBefore, after: achievementSnapshot)
        )
    }

    /// Add a mistaken question to the SRS bank if it isn't already there.
    func recordMistake(lessonId: String, lessonTitle: String?, question: Question, now: Date = Date()) {
        var p = progress
        let exists = p.mistakesBank.contains { $0.lessonId == lessonId && $0.question.id == question.id }
        if !exists {
            p.mistakesBank.append(SRS.newEntry(
                lessonId: lessonId,
                lessonTitle: lessonTitle,
                question: question,
                now: now
            ))
        }
        progress = p
        save()
    }

    /// Apply a review result against the SRS bank. Removes the entry once it
    /// reaches box 3 with at least 2 correct reviews (graduated).
    func reviewMistake(lessonId: String, questionId: Int, isCorrect: Bool, now: Date = Date()) {
        var p = progress
        guard let idx = p.mistakesBank.firstIndex(where: {
            $0.lessonId == lessonId && $0.question.id == questionId
        }) else { return }
        let updated = SRS.review(entry: p.mistakesBank[idx], isCorrect: isCorrect, now: now)
        if (updated.box ?? 1) >= 3 && (updated.correctCount ?? 0) >= 2 {
            p.mistakesBank.remove(at: idx)
        } else {
            p.mistakesBank[idx] = updated
        }
        progress = p
        save()
    }

    /// Persist the user's selected grade preference.
    func setSelectedGrade(_ grade: Int) {
        selectedGrade = grade
        persistPrefs()
    }

    /// Persist which book the user is currently on (the home-tab path).
    func setActiveBook(_ bookId: String?) {
        activeBookId = bookId
        persistPrefs()
    }

    /// Mark first-run onboarding complete.
    func completeOnboarding() {
        hasCompletedOnboarding = true
        persistPrefs()
    }

    private func persistPrefs() {
        try? PersistenceService.write(
            Prefs(
                selectedGrade: selectedGrade,
                activeBookId: activeBookId,
                hasCompletedOnboarding: hasCompletedOnboarding
            ),
            to: Self.prefsFile
        )
    }

    // MARK: - Queries

    func isLessonCompleted(_ lessonId: String) -> Bool {
        progress.completedLessons[lessonId] != nil
    }

    func stars(for lessonId: String) -> Int? {
        progress.completedLessons[lessonId]?.stars
    }

    var totalCompletedLessons: Int { progress.completedLessons.count }
    var perfectedLessonCount: Int { progress.completedLessons.values.filter { $0.stars == 3 }.count }

    /// Snapshot used by Achievements.unlockedIds / newlyUnlocked.
    var achievementSnapshot: AchievementProgressSnapshot {
        AchievementProgressSnapshot(
            xp: progress.xp,
            streak: progress.streak,
            lifetimeGems: progress.lifetimeGems ?? gems,
            completedLessonCount: totalCompletedLessons,
            perfectedLessonCount: perfectedLessonCount,
            ownedCosmeticCount: ownedCosmetics.count,
            reviewedMistakeCount: progress.mistakesBank.filter { ($0.correctCount ?? 0) > 0 }.count
        )
    }

    // MARK: - Gamification Accessors (hearts / gems / daily XP)

    var hearts: Int { progress.hearts ?? Self.maxHearts }
    var gems: Int { progress.gems ?? 0 }
    var dailyGoal: Int { progress.dailyGoal ?? 50 }
    var streakFreezes: Int { progress.streakFreezes ?? 0 }

    /// XP earned today (resets when date changes).
    var todayXp: Int {
        let today = SRS.todayString()
        if progress.lastXpDate == today {
            return progress.todayXp ?? 0
        }
        return 0
    }

    /// Whether the daily XP goal has been reached today.
    var dailyGoalReached: Bool { todayXp >= dailyGoal }

    /// Whether any study activity (lesson / review / reading) happened today.
    var studiedToday: Bool { progress.lastActiveDate == SRS.todayString() }

    /// The streak value that studying today could still continue (incl. shield
    /// coverage): the current streak while it's salvageable, else 0. Shared by
    /// the HUD (`displayStreak`) and the reminder copy (`reminderStreak`) so
    /// neither ever quotes a streak that is already gone.
    func salvageableStreak(now: Date = Date()) -> Int {
        let today = SRS.todayString(now: now)
        if progress.lastActiveDate == today { return progress.streak }
        let adv = Streak.advance(
            streak: progress.streak,
            streakFreezes: progress.streakFreezes ?? 0,
            lastActiveDate: progress.lastActiveDate,
            today: today
        )
        return adv.streak == progress.streak + 1 ? progress.streak : 0
    }

    /// Honest streak for the home HUD: a stale "连续 N 天" never survives a
    /// broken chain — once shields can't cover the gap this drops to 0.
    var displayStreak: Int { salvageableStreak() }

    /// The streak value a reminder may truthfully quote; 0 makes the
    /// notification fall back to generic copy instead of promising to save a
    /// streak that is already gone.
    var reminderStreak: Int { salvageableStreak() }

    /// Unix timestamp (seconds) for the next heart recharge, or nil if full.
    var nextHeartAt: Date? {
        guard let ms = progress.nextHeartAt else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Lose one heart. Called on wrong answer in lesson runner.
    func loseHeart(now: Date = Date()) {
        // Settle any pending recharge first so we never eat a heart the timer
        // already gave back while no UI was ticking it.
        tickHeartRecharge(now: now)
        var p = progress
        let current = p.hearts ?? Self.maxHearts
        guard current > 0 else { return }
        p.hearts = current - 1
        // Start recharge timer if not already running.
        if p.nextHeartAt == nil {
            p.nextHeartAt = (now.timeIntervalSince1970 + Self.heartRechargeSeconds) * 1000
        }
        progress = p
        save()
    }

    /// Tick the heart recharge timer, restoring hearts as needed.
    func tickHeartRecharge(now: Date = Date()) {
        var p = progress
        var currentHearts = p.hearts ?? Self.maxHearts
        guard currentHearts < Self.maxHearts, var nextMs = p.nextHeartAt else { return }
        let nowMs = now.timeIntervalSince1970 * 1000
        while nextMs <= nowMs && currentHearts < Self.maxHearts {
            currentHearts += 1
            nextMs += Self.heartRechargeSeconds * 1000
        }
        p.hearts = currentHearts
        p.nextHeartAt = currentHearts < Self.maxHearts ? nextMs : nil
        progress = p
        save()
    }

    /// Day key the published state was last rendered against — lets
    /// `refreshForNow` detect a calendar rollover while the app was inactive.
    private var lastKnownDay = SRS.todayString()

    /// Re-sync every time-derived piece of state with the wall clock: recharge
    /// hearts, poke observers when the calendar day changed (todayXp /
    /// studiedToday / displayStreak are all computed against "today"), and
    /// refresh the rolling reminder window. Called at launch, on returning to
    /// foreground, and on the system's day-changed notification — so an app
    /// left overnight never shows yesterday's state.
    func refreshForNow(now: Date = Date()) {
        tickHeartRecharge(now: now)
        let today = SRS.todayString(now: now)
        if today != lastKnownDay {
            lastKnownDay = today
            // Derived accessors read the wall clock; nothing stored changed,
            // so fire the publisher by hand to make every view recompute.
            objectWillChange.send()
        }
        NotificationService.shared.rescheduleStreakReminder(
            streak: salvageableStreak(now: now),
            studiedToday: progress.lastActiveDate == today,
            now: now
        )
    }

    /// Refill hearts to max (used by streak freeze or debug).
    func refillHearts() {
        var p = progress
        p.hearts = Self.maxHearts
        p.nextHeartAt = nil
        progress = p
        save()
    }

    /// Add gems (from chest reward, achievements, etc.). Tracks a lifetime total
    /// so "earn N gems" achievements don't reset when the balance is spent.
    func addGems(_ amount: Int) {
        var p = progress
        p.gems = (p.gems ?? 0) + amount
        if amount > 0 { p.lifetimeGems = (p.lifetimeGems ?? 0) + amount }
        progress = p
        save()
    }

    /// Spend gems if enough balance. Returns true if successful.
    @discardableResult
    func spendGems(_ amount: Int) -> Bool {
        var p = progress
        let current = p.gems ?? 0
        guard current >= amount else { return false }
        p.gems = current - amount
        progress = p
        save()
        return true
    }

    /// Spend gems to add one streak freeze shield. Returns true on success.
    @discardableResult
    func buyStreakFreeze(cost: Int = 200) -> Bool {
        guard spendGems(cost) else { return false }
        var p = progress
        p.streakFreezes = (p.streakFreezes ?? 0) + 1
        progress = p
        save()
        return true
    }

    /// Spend gems to refill all hearts. Returns true on success. Ticks the
    /// recharge timer first — hearts that came back on their own while the UI
    /// was stale must never be sold back to the learner for gems.
    @discardableResult
    func buyHeartRefill(cost: Int = 350, now: Date = Date()) -> Bool {
        tickHeartRecharge(now: now)
        guard hearts < Self.maxHearts else { return false }
        guard spendGems(cost) else { return false }
        refillHearts()
        return true
    }

    // MARK: - Cosmetics

    /// Starter cosmetics are owned for free; plus anything purchased.
    var ownedCosmetics: Set<String> {
        Set(Cosmetics.starters.map(\.id)).union(progress.ownedCosmetics ?? [])
    }
    func isOwned(_ id: String) -> Bool { ownedCosmetics.contains(id) }

    var equippedMascotSkin: String { progress.equippedMascotSkin ?? Cosmetics.defaultEquipped.mascotSkin }
    var equippedTheme: String { progress.equippedTheme ?? Cosmetics.defaultEquipped.uiTheme }
    var equippedBackdrop: String { progress.equippedBackdrop ?? Cosmetics.defaultEquipped.lessonBackdrop }

    func isEquipped(_ id: String) -> Bool {
        id == equippedMascotSkin || id == equippedTheme || id == equippedBackdrop
    }

    /// Buy a cosmetic with gems. Returns true on success (or if already owned).
    @discardableResult
    func buyCosmetic(_ item: CosmeticItem) -> Bool {
        if isOwned(item.id) { return true }
        guard spendGems(item.cost) else { return false }
        var p = progress
        var owned = p.ownedCosmetics ?? []
        owned.append(item.id)
        p.ownedCosmetics = owned
        progress = p
        save()
        return true
    }

    /// Equip an owned cosmetic in its slot.
    func equipCosmetic(_ item: CosmeticItem) {
        guard isOwned(item.id) else { return }
        var p = progress
        switch item.type {
        case .mascotSkin:     p.equippedMascotSkin = item.id
        case .uiTheme:        p.equippedTheme = item.id
        case .lessonBackdrop: p.equippedBackdrop = item.id
        }
        progress = p
        save()
        applyEquippedTheme()
    }

    /// The `UiThemeData` behind the equipped theme id (nil for the stock theme).
    var equippedThemeData: UiThemeData? {
        Cosmetics.uiThemes.first { $0.item.id == equippedTheme }?.data
    }

    /// The gradient behind the equipped lesson backdrop (nil for the plain one).
    var equippedBackdropData: LessonBackdropData? {
        Cosmetics.lessonBackdrops.first { $0.item.id == equippedBackdrop }?.data
    }

    /// Push the equipped theme into the design system. Called at launch and
    /// whenever a theme is equipped.
    func applyEquippedTheme() {
        DuoColors.themeOverride = equippedThemeData
    }

    /// Award XP for a mistake review (feeds the daily goal + streak, no hearts).
    /// A session with zero correct answers still counts as review activity —
    /// the quest counter and streak track effort, not the score.
    func awardReviewXP(_ amount: Int, reviewedCount: Int = 0, now: Date = Date()) {
        guard amount > 0 || reviewedCount > 0 else { return }
        var p = progress
        rollDailyIfNeeded(&p, now: now)
        recordXP(&p, amount, now: now)
        p.dailyReviews = (p.dailyReviews ?? 0) + max(0, reviewedCount)
        bumpStreak(&p, now: now)
        progress = p
        save()
        NotificationService.shared.rescheduleStreakReminder(streak: p.streak, studiedToday: true)
    }

    // MARK: - Reading (passages & stories)

    var completedReadings: Set<String> { Set(progress.completedReadings ?? []) }
    func isReadingCompleted(_ id: String) -> Bool { completedReadings.contains(id) }

    /// Mark a passage/story as read. Awards XP + advances the daily goal & streak
    /// the first time only, so reading feeds the same loop as lessons.
    func completeReading(id: String, xp: Int, now: Date = Date()) {
        var p = progress
        var set = Set(p.completedReadings ?? [])
        guard set.insert(id).inserted else { return }   // already read
        p.completedReadings = Array(set)
        rollDailyIfNeeded(&p, now: now)
        recordXP(&p, xp, now: now)
        p.dailyReadings = (p.dailyReadings ?? 0) + 1
        bumpStreak(&p, now: now)
        progress = p
        save()
        NotificationService.shared.rescheduleStreakReminder(streak: p.streak, studiedToday: true)
    }

    // MARK: - Profile

    var displayName: String {
        get { progress.displayName ?? "小学员" }
        set {
            var p = progress
            p.displayName = newValue.isEmpty ? nil : newValue
            progress = p
            save()
        }
    }

    /// Reset all learning progress (used by Settings). Keeps nothing.
    func resetProgress() {
        progress = UserProgress(xp: 0, streak: 0, lastActiveDate: "", completedLessons: [:], mistakesBank: [])
        save()
    }

    /// Set the daily XP goal.
    func setDailyGoal(_ goal: Int) {
        var p = progress
        p.dailyGoal = goal
        progress = p
        save()
    }

    /// Mark a chest as claimed.
    func claimChest(_ chestId: String) {
        var p = progress
        var claimed = p.claimedChests ?? [:]
        claimed[chestId] = true
        p.claimedChests = claimed
        progress = p
        save()
    }

    func isChestClaimed(_ chestId: String) -> Bool {
        progress.claimedChests?[chestId] == true
    }

    /// Mistakes the SRS scheduler thinks are due for review today.
    var dueMistakes: [MistakeEntry] {
        SRS.dueEntries(progress.mistakesBank)
    }

    // MARK: - Internal

    // MARK: - Daily counters, XP history & quests

    /// Roll the per-day counters over when the calendar day changes.
    private func rollDailyIfNeeded(_ p: inout UserProgress, now: Date) {
        let today = SRS.todayString(now: now)
        guard p.dailyDate != today else { return }
        p.dailyDate = today
        p.dailyLessons = 0
        p.dailyReviews = 0
        p.dailyReadings = 0
    }

    /// Single place that records earned XP: lifetime, today, and the rolling
    /// per-day history the weekly report reads.
    private func recordXP(_ p: inout UserProgress, _ amount: Int, now: Date) {
        guard amount > 0 else { return }
        let today = SRS.todayString(now: now)
        p.xp += amount
        if p.lastXpDate == today {
            p.todayXp = (p.todayXp ?? 0) + amount
        } else {
            p.todayXp = amount
            p.lastXpDate = today
        }
        var history = p.xpHistory ?? [:]
        history[today] = (history[today] ?? 0) + amount
        // Keep the map small — the report only ever looks back two weeks.
        if history.count > 21 {
            for key in history.keys.sorted().prefix(history.count - 21) { history.removeValue(forKey: key) }
        }
        p.xpHistory = history
    }

    /// Today's three quests (stable for the calendar day).
    var todayQuests: [Quest] { Quests.daily(for: SRS.todayString()) }

    /// How far along today's counters are for a given quest.
    func questProgress(_ quest: Quest, now: Date = Date()) -> Int {
        let today = SRS.todayString(now: now)
        guard progress.dailyDate == today else {
            // Counters belong to a previous day — only XP has its own tracking.
            return quest.kind == .earnXP ? todayXp : 0
        }
        switch quest.kind {
        case .earnXP:          return todayXp
        case .finishLessons:   return progress.dailyLessons ?? 0
        case .reviewMistakes:  return progress.dailyReviews ?? 0
        case .readTexts:       return progress.dailyReadings ?? 0
        }
    }

    func isQuestComplete(_ quest: Quest) -> Bool { questProgress(quest) >= quest.target }

    private func questKey(_ quest: Quest, now: Date = Date()) -> String {
        "\(SRS.todayString(now: now)):\(quest.id)"
    }

    func isQuestClaimed(_ quest: Quest) -> Bool {
        (progress.claimedQuests ?? []).contains(questKey(quest))
    }

    /// Claim a finished quest's gem reward. Returns false if not claimable.
    @discardableResult
    func claimQuest(_ quest: Quest) -> Bool {
        guard isQuestComplete(quest), !isQuestClaimed(quest) else { return false }
        var p = progress
        var claimed = p.claimedQuests ?? []
        claimed.append(questKey(quest))
        // Trim old claims so the ledger doesn't grow forever.
        if claimed.count > 60 { claimed.removeFirst(claimed.count - 60) }
        p.claimedQuests = claimed
        progress = p
        addGems(quest.reward)   // persists
        return true
    }

    /// XP earned on each of the last `days` days, oldest first.
    func recentXP(days: Int = 7, now: Date = Date()) -> [(date: String, xp: Int)] {
        let history = progress.xpHistory ?? [:]
        return (0..<days).reversed().map { offset in
            let key = SRS.dateString(daysFromNow: -offset, now: now)
            return (key, history[key] ?? 0)
        }
    }

    /// Total XP over the 7 days ending `endingDaysAgo` days back.
    func weeklyTotal(endingDaysAgo: Int = 0, now: Date = Date()) -> Int {
        let history = progress.xpHistory ?? [:]
        return (0..<7).reduce(0) { sum, i in
            sum + (history[SRS.dateString(daysFromNow: -(i + endingDaysAgo), now: now)] ?? 0)
        }
    }

    private func bumpStreak(_ p: inout UserProgress, now: Date) {
        let adv = Streak.advance(
            streak: p.streak,
            streakFreezes: p.streakFreezes ?? 0,
            lastActiveDate: p.lastActiveDate,
            today: SRS.todayString(now: now)
        )
        p.streak = adv.streak
        p.streakFreezes = adv.streakFreezes
        p.lastActiveDate = adv.lastActiveDate
    }

    private func save() {
        try? PersistenceService.write(progress, to: Self.progressFile)
    }
}
