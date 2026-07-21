import Foundation

/// Daily quests — three per day, chosen deterministically from the date so the
/// set is stable for a given day without any server involvement.

enum QuestKind: String, Codable, Hashable, CaseIterable {
    case earnXP        // earn N XP today
    case finishLessons // complete N lessons today
    case reviewMistakes// review N mistakes today
    case readTexts     // finish N passages/stories today

    var symbol: String {
        switch self {
        case .earnXP:         return "bolt.fill"
        case .finishLessons:  return "checkmark.seal.fill"
        case .reviewMistakes: return "arrow.triangle.2.circlepath"
        case .readTexts:      return "book.fill"
        }
    }
}

struct Quest: Identifiable, Hashable {
    let kind: QuestKind
    let target: Int
    let reward: Int          // gems

    /// Stable within a day — the claim ledger keys off `"\(date):\(id)"`.
    var id: String { "\(kind.rawValue)-\(target)" }

    var title: String {
        switch kind {
        case .earnXP:         return "获得 \(target) 点经验"
        case .finishLessons:  return "完成 \(target) 节小课"
        case .reviewMistakes: return "复习 \(target) 道错题"
        case .readTexts:      return "读完 \(target) 篇课文或故事"
        }
    }
}

enum Quests {
    /// Candidate pool. Kept small and achievable — these are daily habits,
    /// not grinds.
    private static let pool: [Quest] = [
        Quest(kind: .earnXP, target: 30, reward: 10),
        Quest(kind: .earnXP, target: 60, reward: 15),
        Quest(kind: .earnXP, target: 100, reward: 25),
        Quest(kind: .finishLessons, target: 1, reward: 10),
        Quest(kind: .finishLessons, target: 2, reward: 20),
        Quest(kind: .finishLessons, target: 3, reward: 30),
        Quest(kind: .reviewMistakes, target: 1, reward: 10),
        Quest(kind: .reviewMistakes, target: 3, reward: 20),
        Quest(kind: .readTexts, target: 1, reward: 15),
        Quest(kind: .readTexts, target: 2, reward: 25),
    ]

    /// SplitMix64 finalizer. A plain rolling hash leaves the high bits nearly
    /// identical for consecutive dates (the last character only feeds the low
    /// bits), which collapsed the variety to a handful of sets per month — so
    /// every derived index gets avalanched through this first.
    private static func mix(_ value: UInt64) -> UInt64 {
        var x = value &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    /// Three quests of distinct kinds for the given day, derived from the date
    /// string so every launch on the same day yields the same set.
    static func daily(for dateString: String) -> [Quest] {
        var hash = UInt64(5381)
        for byte in dateString.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        hash = mix(hash)

        func index(_ count: Int, salt: UInt64) -> Int {
            guard count > 0 else { return 0 }
            return Int(mix(hash &+ salt) % UInt64(count))
        }
        func pick(_ kind: QuestKind, salt: UInt64) -> Quest {
            let options = pool.filter { $0.kind == kind }
            return options[index(options.count, salt: salt)]
        }

        // Always an XP quest, then two other kinds — drawn without replacement
        // so a day never offers the same kind twice.
        var rest: [QuestKind] = [.finishLessons, .reviewMistakes, .readTexts]
        let firstKind = rest.remove(at: index(rest.count, salt: 0x11))
        let secondKind = rest[index(rest.count, salt: 0x22)]

        return [
            pick(.earnXP, salt: 0x01),
            pick(firstKind, salt: 0x33),
            pick(secondKind, salt: 0x44),
        ]
    }
}
