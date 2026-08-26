import Foundation

/// All push destinations used by the root NavigationStack. Adding a new screen
/// is a one-line edit here + a `case` in `RootView.navigationDestination`.
enum AppRoute: Hashable {
    case bookList(grade: Int)
    case bookDetail(bookId: String)
    case lesson(bookId: String, lessonId: String)
    case lessonResult(LessonRunResult)
    case review
    case reviewRunner
    case achievements
    case stories(bookId: String)
    case storyReader(bookId: String, storyId: String)
    case reading(bookId: String)
    case passageReader(bookId: String, passageId: String)
    case shop
    case profile
    case settings
}

/// Result of committing a finished lesson to the store — single source of
/// truth for the XP/streak numbers the result screen celebrates.
struct LessonOutcome: Hashable {
    var xpGained: Int = 0
    var stars: Int = 1
    var streakBefore: Int = 0
    var streakAfter: Int = 0
    var dailyGoalReachedNow: Bool = false
    var gemsGained: Int = 0
    var newAchievements: [Achievement] = []
    /// Streak-milestone gems banked by this lesson (0 = no milestone hit).
    var milestoneGems: Int = 0
    /// Whether the weekend ×2 multiplier was applied to `xpGained`.
    var weekendDoubled: Bool = false
    /// Streak shields consumed covering missed days (ios-economy-6) — the
    /// result screen shows「❄️ 护盾保住了你的连胜」when > 0.
    var freezesConsumed: Int = 0
    var streakIncreased: Bool { streakAfter > streakBefore }
}

/// Snapshot pushed onto the navigation stack after a lesson finishes.
struct LessonRunResult: Hashable {
    let bookId: String
    let lessonId: String
    let lessonTitle: String
    let questionCount: Int
    let correctCount: Int
    var outcome: LessonOutcome = LessonOutcome()
    var accuracy: Double {
        guard questionCount > 0 else { return 0 }
        return Double(correctCount) / Double(questionCount)
    }
    var stars: Int { Economy.starsFromAccuracy(accuracy) }
}
