import Foundation

/// Streak advance + streak-freeze consumption — ports the GAP handling of
/// `bumpStreakIfNeeded` (apps/web/src/store/progress.ts). Web's extra
/// retention mechanics (Monday shield top-up, 2-shield starting balance,
/// streak milestone gems) are NOT ported yet — they belong to the
/// cross-platform parity pass, tracked in the roadmap.
enum Streak {
    struct Advance: Equatable {
        var streak: Int
        var streakFreezes: Int
        var lastActiveDate: String
        /// Shields consumed to cover missed days (0 = none needed).
        var freezesConsumed: Int
    }

    /// Compute the streak state after studying on `today` (a "yyyy-MM-dd" string).
    ///
    /// - Same day: no change.
    /// - 1-day gap: streak continues.
    /// - Longer gap: one shield covers each missed day when enough are banked;
    ///   otherwise the streak resets to 1 (today still counts).
    static func advance(
        streak: Int,
        streakFreezes: Int,
        lastActiveDate: String,
        today: String
    ) -> Advance {
        if lastActiveDate == today {
            return Advance(streak: streak, streakFreezes: streakFreezes,
                           lastActiveDate: today, freezesConsumed: 0)
        }
        if lastActiveDate.isEmpty {
            return Advance(streak: 1, streakFreezes: streakFreezes,
                           lastActiveDate: today, freezesConsumed: 0)
        }
        let gap = SRS.daysBetween(lastActiveDate, today)
        if gap == 1 {
            return Advance(streak: streak + 1, streakFreezes: streakFreezes,
                           lastActiveDate: today, freezesConsumed: 0)
        }
        if gap > 1 {
            let missed = gap - 1
            if streakFreezes >= missed {
                return Advance(streak: streak + 1, streakFreezes: streakFreezes - missed,
                               lastActiveDate: today, freezesConsumed: missed)
            }
            return Advance(streak: 1, streakFreezes: streakFreezes,
                           lastActiveDate: today, freezesConsumed: 0)
        }
        // gap <= 0: stored date is today-or-later (clock rolled back). Web
        // leaves the state untouched in this case; do the same.
        return Advance(streak: streak, streakFreezes: streakFreezes,
                       lastActiveDate: lastActiveDate, freezesConsumed: 0)
    }
}
