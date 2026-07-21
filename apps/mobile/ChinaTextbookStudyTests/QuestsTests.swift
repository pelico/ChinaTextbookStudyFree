import XCTest
@testable import ChinaTextbookStudy

/// Daily quests are generated from the date so they stay stable for a day
/// without a server. These pin that contract down.
final class QuestsTests: XCTestCase {

    func testAlwaysReturnsThreeQuests() {
        for day in ["2026-07-20", "2026-01-01", "2025-12-31", "2026-02-28"] {
            XCTAssertEqual(Quests.daily(for: day).count, 3, "expected 3 quests for \(day)")
        }
    }

    func testIsDeterministicForTheSameDay() {
        let a = Quests.daily(for: "2026-07-20")
        let b = Quests.daily(for: "2026-07-20")
        XCTAssertEqual(a.map(\.id), b.map(\.id),
                       "the same date must always yield the same quest set")
    }

    func testKindsAreDistinctWithinADay() {
        for day in ["2026-07-20", "2026-07-21", "2026-07-22", "2026-08-05", "2026-11-11"] {
            let kinds = Quests.daily(for: day).map(\.kind)
            XCTAssertEqual(Set(kinds).count, kinds.count,
                           "quest kinds should not repeat within \(day): \(kinds)")
        }
    }

    func testAlwaysIncludesAnXPQuest() {
        for day in ["2026-07-20", "2026-03-03", "2026-09-09"] {
            XCTAssertTrue(Quests.daily(for: day).contains { $0.kind == .earnXP },
                          "every day should offer an XP quest (\(day))")
        }
    }

    func testSetVariesAcrossDays() {
        let days = (1...28).map { String(format: "2026-07-%02d", $0) }
        let signatures = Set(days.map { Quests.daily(for: $0).map(\.id).joined(separator: "|") })
        XCTAssertGreaterThan(signatures.count, 3,
                             "quests should vary across the month, got \(signatures.count) distinct sets")
    }

    func testTargetsAndRewardsArePositive() {
        for day in ["2026-07-20", "2026-05-05"] {
            for quest in Quests.daily(for: day) {
                XCTAssertGreaterThan(quest.target, 0, "\(quest.id) target must be > 0")
                XCTAssertGreaterThan(quest.reward, 0, "\(quest.id) reward must be > 0")
                XCTAssertFalse(quest.title.isEmpty)
            }
        }
    }
}
