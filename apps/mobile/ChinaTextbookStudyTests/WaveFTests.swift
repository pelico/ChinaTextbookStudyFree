import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave F regressions (Dynamic Type scaling + review-prompt ledger)

/// Covers the Wave F polish work:
/// - `DuoFont.scaledSize(for:)` really scales with the content size category,
///   and the two metadata roles (`caption` / `micro`) are capped at ~1.35×.
/// - `ReviewPrompter`'s local ledger allows at most 2 rating requests per app
///   version and resets when the version changes.
final class WaveFTests: XCTestCase {

    // MARK: - DuoFont Dynamic Type

    /// At the default (Large) category every role renders at its base size.
    func testDuoFontDefaultCategoryKeepsBaseSize() {
        for role in DuoFont.allCases {
            XCTAssertEqual(
                role.scaledSize(for: .large), role.size, accuracy: 0.5,
                "\(role) should render at its base size in the default category"
            )
        }
    }

    /// Reading roles grow at accessibility sizes — Dynamic Type is real, not
    /// a recorded intention.
    func testDuoFontReadingRolesGrowAtAccessibilitySizes() {
        for role in [DuoFont.body, .subhead, .heading, .title] {
            XCTAssertGreaterThan(
                role.scaledSize(for: .accessibilityExtraExtraExtraLarge), role.size,
                "\(role) should grow beyond its base size at AX sizes"
            )
        }
    }

    /// caption / micro are capped at 1.35× so chips and badges never explode
    /// a layout at the biggest accessibility settings.
    func testDuoFontMetadataRolesAreCapped() {
        for role in [DuoFont.caption, .micro] {
            let cap = role.size * 1.35
            XCTAssertLessThanOrEqual(
                role.scaledSize(for: .accessibilityExtraExtraExtraLarge), cap + 0.01,
                "\(role) must not exceed its 1.35× cap"
            )
            // The cap should actually bite at the extreme end (the uncapped
            // caption2/footnote curves scale well past 1.35×).
            XCTAssertEqual(
                role.scaledSize(for: .accessibilityExtraExtraExtraLarge), cap, accuracy: 0.01,
                "\(role) should sit exactly on the cap at AX5"
            )
        }
    }

    /// The cap never *shrinks* text at moderate sizes — at XL the scaled value
    /// stays within the ceiling (it may land exactly on it), so the min() only
    /// ever clamps, never bites below the natural scale.
    func testDuoFontCapDoesNotBiteAtModerateSizes() {
        for role in [DuoFont.caption, .micro] {
            XCTAssertGreaterThanOrEqual(role.scaledSize(for: .extraLarge), role.size)
            XCTAssertLessThanOrEqual(role.scaledSize(for: .extraLarge), role.size * 1.35)
        }
    }

    /// Bigger category ⇒ never-smaller text, for every role (monotonicity).
    func testDuoFontScalingIsMonotonic() {
        let ladder: [UIContentSizeCategory] = [
            .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge
        ]
        for role in DuoFont.allCases {
            var last: CGFloat = 0
            for category in ladder {
                let value = role.scaledSize(for: category)
                XCTAssertGreaterThanOrEqual(
                    value + 0.01, last,
                    "\(role) should scale monotonically (broke at \(category.rawValue))"
                )
                last = value
            }
        }
    }

    // MARK: - ReviewPrompter ledger (critic-8)

    private var defaults: UserDefaults!
    private let suiteName = "wave-f-review-prompter-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testReviewPrompterAllowsFirstRequest() {
        XCTAssertTrue(ReviewPrompter.shouldRequest(version: "1.0", defaults: defaults))
    }

    func testReviewPrompterCapsAtTwoPerVersion() {
        ReviewPrompter.recordRequest(version: "1.0", defaults: defaults)
        XCTAssertTrue(
            ReviewPrompter.shouldRequest(version: "1.0", defaults: defaults),
            "second request in the same version is still allowed"
        )
        ReviewPrompter.recordRequest(version: "1.0", defaults: defaults)
        XCTAssertFalse(
            ReviewPrompter.shouldRequest(version: "1.0", defaults: defaults),
            "third request in the same version must be denied"
        )
    }

    func testReviewPrompterResetsOnNewVersion() {
        ReviewPrompter.recordRequest(version: "1.0", defaults: defaults)
        ReviewPrompter.recordRequest(version: "1.0", defaults: defaults)
        XCTAssertFalse(ReviewPrompter.shouldRequest(version: "1.0", defaults: defaults))

        // A new app version starts a fresh budget…
        XCTAssertTrue(ReviewPrompter.shouldRequest(version: "1.1", defaults: defaults))
        ReviewPrompter.recordRequest(version: "1.1", defaults: defaults)
        XCTAssertTrue(ReviewPrompter.shouldRequest(version: "1.1", defaults: defaults))
        ReviewPrompter.recordRequest(version: "1.1", defaults: defaults)
        XCTAssertFalse(ReviewPrompter.shouldRequest(version: "1.1", defaults: defaults))
    }

    func testReviewPrompterRecordCountsPerVersion() {
        ReviewPrompter.recordRequest(version: "1.0", defaults: defaults)
        ReviewPrompter.recordRequest(version: "2.0", defaults: defaults)
        // The 2.0 record replaced the 1.0 ledger — count restarted at 1, so a
        // second 2.0 request is still available.
        XCTAssertTrue(ReviewPrompter.shouldRequest(version: "2.0", defaults: defaults))
    }
}
