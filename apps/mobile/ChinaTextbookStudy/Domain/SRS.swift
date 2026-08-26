import Foundation

/// Simplified Leitner 3-box spaced repetition — port of packages/core/src/srs.ts.
///
/// Boxes:
///   - 1 → review today
///   - 2 → review tomorrow
///   - 3 → review in 3 days, then 7 days
///
/// Wrong answer demotes to box 1. Right answer promotes by one box.
enum SRS {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func todayString(now: Date = Date()) -> String {
        dateFormatter.string(from: now)
    }

    static func dateString(daysFromNow days: Int, now: Date = Date()) -> String {
        let target = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return dateFormatter.string(from: target)
    }

    /// Whole-day difference between two "yyyy-MM-dd" strings (`to` − `from`).
    /// Unparseable input counts as an arbitrarily large gap.
    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = dateFormatter.date(from: from),
              let b = dateFormatter.date(from: to) else { return Int.max }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? Int.max
    }

    /// Apply a review result to an existing entry and return the updated copy.
    static func review(entry: MistakeEntry, isCorrect: Bool, now: Date = Date()) -> MistakeEntry {
        var next = entry
        next.lastReviewedAt = isoFormatter.string(from: now)

        if !isCorrect {
            next.box = 1
            next.correctCount = 0
            next.nextReviewDate = todayString(now: now)
            return next
        }

        next.correctCount = (entry.correctCount ?? 0) + 1
        let currentBox = entry.box ?? 1
        switch currentBox {
        case 1:
            next.box = 2
            next.nextReviewDate = dateString(daysFromNow: 1, now: now)
        case 2:
            next.box = 3
            next.nextReviewDate = dateString(daysFromNow: 3, now: now)
        default:
            next.box = 3
            next.nextReviewDate = dateString(daysFromNow: 7, now: now)
        }
        return next
    }

    // MARK: - 毕业判定（core `isSrsGraduated` 的逐行镜像）

    /// 毕业线（盒子）：至少升到 box 3。
    static let graduateMinBox = 3
    /// 毕业线（答对次数）：累计答对达到该值。
    static let graduateMinCorrect = 2

    /// 条目是否达到毕业语义：**显式 graduated 标记，或 box ≥ 3 且累计答对 ≥ 2**。
    ///
    /// ⚠️ 这是派生判定，不是「只认显式标记」：老档 / 从另一端导入的条目常常
    /// 只有 box + correctCount 而没有 graduated 字段，只认标记会让它们永远
    /// 留在 due 队列里反复出现。与 core `isSrsGraduated` 同源，
    /// spec/golden-vectors.json 的 `srsGraduation` 组两端对照。
    static func isGraduated(graduated: Bool?, box: Int?, correctCount: Int?) -> Bool {
        if graduated == true { return true }
        return (box ?? 1) >= graduateMinBox && (correctCount ?? 0) >= graduateMinCorrect
    }

    /// 错题条目的毕业判定。
    static func isGraduated(_ entry: MistakeEntry) -> Bool {
        isGraduated(graduated: entry.graduated, box: entry.box, correctCount: entry.correctCount)
    }

    /// Filter & sort entries that are due today.
    /// Lower box first; within a box, oldest `lastReviewedAt` (or `addedAt`) first.
    /// 毕业条目（派生判定）永不进入 due 队列 —— 与 core `getDueSrsEntries` 一致。
    static func dueEntries(_ entries: [MistakeEntry], now: Date = Date()) -> [MistakeEntry] {
        let today = todayString(now: now)
        let due = entries.filter { e in
            if isGraduated(e) { return false }
            guard let next = e.nextReviewDate else { return true }
            return next <= today
        }
        return due.sorted { a, b in
            let ba = a.box ?? 1
            let bb = b.box ?? 1
            if ba != bb { return ba < bb }
            let la = a.lastReviewedAt ?? a.addedAt
            let lb = b.lastReviewedAt ?? b.addedAt
            return la < lb
        }
    }

    /// Build a new mistake entry with default SRS scheduling fields.
    static func newEntry(
        lessonId: String,
        lessonTitle: String? = nil,
        question: Question,
        now: Date = Date()
    ) -> MistakeEntry {
        MistakeEntry(
            lessonId: lessonId,
            lessonTitle: lessonTitle,
            question: question,
            addedAt: isoFormatter.string(from: now),
            box: 1,
            correctCount: 0,
            lastReviewedAt: nil,
            nextReviewDate: todayString(now: now)
        )
    }
}
