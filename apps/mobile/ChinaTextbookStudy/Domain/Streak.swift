import Foundation

/// Streak advance + streak-freeze consumption — the date-string front-end of
/// the shared economy rules. The pure gap arithmetic (incl. the Monday shield
/// top-up) lives in `Economy.advanceStreak`, mirroring
/// packages/core/src/economy.ts `advanceStreak`.
enum Streak {
    struct Advance: Equatable {
        var streak: Int
        var streakFreezes: Int
        var lastActiveDate: String
        /// Shields consumed to cover missed days (0 = none needed).
        var freezesConsumed: Int
    }

    /// Whether a "yyyy-MM-dd" day string falls on a local Monday.
    static func isMonday(_ day: String) -> Bool {
        guard let d = SRS.dateFormatter.date(from: day) else { return false }
        return Economy.isMonday(d)
    }

    /// Compute the streak state after studying on `today` (a "yyyy-MM-dd" string).
    ///
    /// - Same day: no change.
    /// - 1-day gap: streak continues; on a Monday an unfilled shield slot is
    ///   topped up by 1 (capped at `Economy.maxFreezes`).
    /// - Longer gap: one shield covers each missed day when enough are banked;
    ///   otherwise the streak resets to 1 (today still counts, shields kept).
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
        if gap <= 0 {
            // Stored date is today-or-later (clock rolled back). Web leaves
            // the state untouched in this case; do the same.
            return Advance(streak: streak, streakFreezes: streakFreezes,
                           lastActiveDate: lastActiveDate, freezesConsumed: 0)
        }
        let r = Economy.advanceStreak(
            streak: streak,
            freezes: streakFreezes,
            gapDays: gap,
            isMonday: isMonday(today)
        )
        return Advance(streak: r.streak, streakFreezes: r.freezes,
                       lastActiveDate: today, freezesConsumed: r.freezesConsumed)
    }
}
