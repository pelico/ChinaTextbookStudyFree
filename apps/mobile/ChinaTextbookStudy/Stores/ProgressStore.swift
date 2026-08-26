import Foundation
import Combine

/// User progress store — port of apps/web/src/store/progress.ts.
///
/// State is persisted to `Application Support/cstf/progress.json` after every
/// mutation.
@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    static let maxHearts = Economy.maxHearts
    /// 5 minutes per heart, matching the shared economy spec.
    static let heartRechargeSeconds: TimeInterval = TimeInterval(Economy.heartRegenSeconds)

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
            var fresh = Self.freshProgress()
            fresh.gems = 500
            fresh.hearts = Self.maxHearts
            // Keep UI tests deterministic: no login-reward card popping over
            // the flows under test.
            fresh.lastDailyRewardDate = SRS.todayString()
            self.progress = fresh
            self.selectedGrade = 1
            self.activeBookId = "g1up"
            self.hasCompletedOnboarding = true
            return
        }
        #endif

        if let restored = PersistenceService.read(UserProgress.self, from: Self.progressFile) {
            var p = restored
            // One-time shield migration: old saves get topped up to the new
            // 2-shield baseline; anything above 2 is kept (never confiscated),
            // only new purchases are capped.
            if p.freezesMigrated != true {
                p.streakFreezes = max(p.streakFreezes ?? 0, Economy.initialFreezes)
                p.freezesMigrated = true
            }
            self.progress = p
        } else {
            self.progress = Self.freshProgress()
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

        // One-time achievement-ledger migration, aligned with web's persist
        // migrate: historical unlocks enter the permanent ledger silently —
        // no retroactive gem payout. Only unlocks from here on pay rewards.
        if progress.unlockedAchievements == nil {
            var p = progress
            p.unlockedAchievements = Achievements.latchUnlocked(
                prevLedger: [],
                currentUnlockedIds: Achievements.unlockedIds(for: snapshot(of: p))
            )
            progress = p
        }
    }

    // MARK: - Mutations

    /// A brand-new save file: Wave B economy baseline (2 streak shields).
    private static func freshProgress() -> UserProgress {
        var p = UserProgress(
            xp: 0,
            streak: 0,
            lastActiveDate: "",
            completedLessons: [:],
            mistakesBank: []
        )
        p.streakFreezes = Economy.initialFreezes
        p.freezesMigrated = true
        return p
    }

    /// Award XP + record the result for a finished lesson.
    ///
    /// Wave B economy (single source of truth = packages/core/src/economy.ts):
    ///   - accuracy = first-try correct / total; stars via `Economy.starsFromAccuracy`
    ///   - XP = correctCount×10, +5 perfect, +5 first-ever 3 stars, weekend ×2
    ///   - gems via `Economy.lessonGemDrip`; streak milestones + achievement
    ///     rewards are banked on top (reported separately in the outcome).
    @discardableResult
    func completeLesson(
        lessonId: String,
        correctCount: Int,
        questionCount: Int,
        now: Date = Date()
    ) -> LessonOutcome {
        // Hearts may have recharged while the learner sat in the lesson —
        // settle the timer before anything below reads a stale count.
        tickHeartRecharge(now: now)

        let total = max(1, questionCount)
        let correct = min(max(0, correctCount), total)
        let accuracy = Double(correct) / Double(total)
        let stars = Economy.starsFromAccuracy(accuracy)
        let perfect = correct >= total
        let isWeekend = Economy.isWeekend(now)

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

        var p = progress
        rollDailyIfNeeded(&p, now: now)

        let priorStars = p.completedLessons[lessonId]?.stars ?? 0
        let firstPerfect = stars == 3 && priorStars < 3

        let xpGain = Economy.xpForLesson(
            correctCount: correct,
            perfect: perfect,
            firstPerfect: firstPerfect,
            isWeekend: isWeekend
        )
        recordXP(&p, xpGain, now: now)
        p.dailyLessons = (p.dailyLessons ?? 0) + 1

        // Take the best result so a re-run can only improve stars.
        if let prior = p.completedLessons[lessonId] {
            if stars >= prior.stars { p.completedLessons[lessonId] = result }
        } else {
            p.completedLessons[lessonId] = result
        }
        let milestoneGems = bumpStreak(&p, now: now)

        let dailyGoalReachedNow = todayXpBefore < goal && (p.todayXp ?? 0) >= goal
        let gemsGained = Economy.lessonGemDrip(
            stars: stars,
            isFirstPerfect: firstPerfect,
            crossedDailyGoal: dailyGoalReachedNow
        )
        p.gems = (p.gems ?? 0) + gemsGained
        p.lifetimeGems = (p.lifetimeGems ?? 0) + gemsGained

        let newAchievements = latchAchievements(&p)

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
            newAchievements: newAchievements,
            milestoneGems: milestoneGems,
            weekendDoubled: isWeekend && xpGain > 0
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
        // Latch before the graduated entry disappears from the bank — the
        // permanent ledger is what keeps "first-review" from re-locking when
        // reviewed mistakes graduate out.
        _ = latchAchievements(&p)
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

    /// Unlocked achievements = the permanent ledger ∪ whatever the live
    /// snapshot currently satisfies. The union means a badge shown as earned
    /// can never flip back to locked when a streak breaks or a reviewed
    /// mistake graduates out of the bank.
    var unlockedAchievementIds: Set<String> {
        Set(progress.unlockedAchievements ?? [])
            .union(Achievements.unlockedIds(for: achievementSnapshot))
    }

    // MARK: - Gamification Accessors (hearts / gems / daily XP)

    var hearts: Int { progress.hearts ?? Self.maxHearts }
    var gems: Int { progress.gems ?? 0 }
    var dailyGoal: Int { progress.dailyGoal ?? Economy.defaultDailyGoal }
    var streakFreezes: Int { progress.streakFreezes ?? 0 }

    /// A login reward claimed this launch/foreground that the UI hasn't
    /// presented yet. HomeView shows a light card and clears it.
    @Published var pendingDailyReward: DailyRewardClaim?

    struct DailyRewardClaim: Equatable {
        /// Gems banked by this claim.
        let gems: Int
        /// The effective (salvageable) streak the tier was read from; 0 when
        /// the chain is broken — copy must not brag about a dead streak.
        let effectiveStreak: Int
    }

    /// Claim today's login reward if it hasn't been claimed yet (once per
    /// local day, `lastDailyRewardDate` ledger). Tier = min(有效连胜, 7); a
    /// broken chain honestly drops to tier 0. Publishes `pendingDailyReward`
    /// for the home screen to celebrate.
    func claimDailyRewardIfDue(now: Date = Date()) {
        let today = SRS.todayString(now: now)
        guard progress.lastDailyRewardDate != today else { return }
        let effectiveStreak = salvageableStreak(now: now)
        let gems = Economy.dailyRewardForStreak(effectiveStreak)
        var p = progress
        p.lastDailyRewardDate = today
        p.gems = (p.gems ?? 0) + gems
        p.lifetimeGems = (p.lifetimeGems ?? 0) + gems
        progress = p
        save()
        pendingDailyReward = DailyRewardClaim(gems: gems, effectiveStreak: effectiveStreak)
    }

    /// Spend 50 gems to pull `lastActiveDate` back to yesterday, reviving a
    /// streak the shields could not cover. Only offered when nothing was
    /// studied today AND the gap is ≥2 days AND the chain is otherwise dead.
    @discardableResult
    func makeUpYesterdayStreak(now: Date = Date()) -> Bool {
        let today = SRS.todayString(now: now)
        guard progress.streak > 0,
              !progress.lastActiveDate.isEmpty,
              progress.lastActiveDate != today,
              SRS.daysBetween(progress.lastActiveDate, today) >= 2,
              salvageableStreak(now: now) == 0
        else { return false }
        guard spendGems(Economy.streakMakeupCost) else { return false }
        var p = progress
        p.lastActiveDate = SRS.dateString(daysFromNow: -1, now: now)
        progress = p
        save()
        return true
    }

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
        claimDailyRewardIfDue(now: now)
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

    /// Add gems (from chest reward, quests, etc.). Tracks a lifetime total
    /// so "earn N gems" achievements don't reset when the balance is spent.
    func addGems(_ amount: Int) {
        var p = progress
        p.gems = (p.gems ?? 0) + amount
        if amount > 0 { p.lifetimeGems = (p.lifetimeGems ?? 0) + amount }
        _ = latchAchievements(&p)   // gem-collector can unlock right here
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

    /// Spend gems to add one streak freeze shield. Holdings are capped at
    /// `Economy.maxFreezes` (legacy saves above the cap keep what they have —
    /// they just can't buy more). Returns true on success.
    @discardableResult
    func buyStreakFreeze(cost: Int = Economy.freezeCost) -> Bool {
        guard streakFreezes < Economy.maxFreezes else { return false }
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
    func buyHeartRefill(cost: Int = Economy.heartRefillCost, now: Date = Date()) -> Bool {
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
        _ = latchAchievements(&p)   // first-cosmetic
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
        _ = latchAchievements(&p)
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
        _ = latchAchievements(&p)
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
        progress = Self.freshProgress()
        pendingDailyReward = nil
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

    /// Advance the streak for study activity on `now`, then pay out any
    /// newly-reached streak milestone (once per tier, `claimedStreakRewards`
    /// ledger). Returns the milestone gems banked (0 = none).
    @discardableResult
    private func bumpStreak(_ p: inout UserProgress, now: Date) -> Int {
        let adv = Streak.advance(
            streak: p.streak,
            streakFreezes: p.streakFreezes ?? 0,
            lastActiveDate: p.lastActiveDate,
            today: SRS.todayString(now: now)
        )
        p.streak = adv.streak
        p.streakFreezes = adv.streakFreezes
        p.lastActiveDate = adv.lastActiveDate

        let reward = Economy.streakMilestoneReward(p.streak)
        var claimed = p.claimedStreakRewards ?? []
        guard reward > 0, !claimed.contains(p.streak) else { return 0 }
        claimed.append(p.streak)
        p.claimedStreakRewards = claimed
        p.gems = (p.gems ?? 0) + reward
        p.lifetimeGems = (p.lifetimeGems ?? 0) + reward
        return reward
    }

    // MARK: - Achievement ledger (permanent, never re-locks)

    /// Snapshot of an arbitrary progress value (not necessarily the published
    /// one) — used to latch achievements mid-mutation.
    private func snapshot(of p: UserProgress) -> AchievementProgressSnapshot {
        AchievementProgressSnapshot(
            xp: p.xp,
            streak: p.streak,
            lifetimeGems: p.lifetimeGems ?? (p.gems ?? 0),
            completedLessonCount: p.completedLessons.count,
            perfectedLessonCount: p.completedLessons.values.filter { $0.stars == 3 }.count,
            ownedCosmeticCount: Set(Cosmetics.starters.map(\.id)).union(p.ownedCosmetics ?? []).count,
            reviewedMistakeCount: p.mistakesBank.filter { ($0.correctCount ?? 0) > 0 }.count
        )
    }

    /// Merge currently-unlocked achievements into the permanent
    /// `unlockedAchievements` ledger (only ever grows — a streak falling back
    /// can never re-lock an earned badge) and pay each newly-latched
    /// achievement's gem reward exactly once. Returns the newly unlocked ones.
    private func latchAchievements(_ p: inout UserProgress) -> [Achievement] {
        let current = Achievements.unlockedIds(for: snapshot(of: p))
        let ledger = p.unlockedAchievements ?? []
        let ledgerSet = Set(ledger)
        let newlyUnlocked = Achievements.all.filter {
            current.contains($0.id) && !ledgerSet.contains($0.id)
        }
        guard !newlyUnlocked.isEmpty else { return [] }
        p.unlockedAchievements = Achievements.latchUnlocked(prevLedger: ledger, currentUnlockedIds: current)
        let reward = newlyUnlocked.reduce(0) { $0 + $1.reward }
        p.gems = (p.gems ?? 0) + reward
        p.lifetimeGems = (p.lifetimeGems ?? 0) + reward
        return newlyUnlocked
    }

    private func save() {
        try? PersistenceService.write(progress, to: Self.progressFile)
    }
}
